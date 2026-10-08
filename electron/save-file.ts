/** save_data.json 직렬화/검증. 파일시스템·electron에 의존하지 않아 단독 테스트가 가능하다. */

export const SCHEMA_VERSION = 1;
export const ALLOWED_FILES = ["savedata.dat", "musicdata.dat", "keypad.dat"] as const;
export const MAX_FILE_BYTES = 1024 * 1024;

export type RawFiles = Record<string, Uint8Array>;

const SAVEDATA_SIZE = 0x334;

const readCString = (bytes: Uint8Array, encoding: string): string => {
  const end = bytes.indexOf(0);
  const slice = end < 0 ? bytes : bytes.subarray(0, end);
  try { return new TextDecoder(encoding).decode(slice); } catch { return new TextDecoder("latin1").decode(slice); }
};

/** 사람이 읽기 위한 참고용 뷰. 로드 시에는 절대 사용하지 않는다(정본은 raw). */
export const decodeForHumans = (files: RawFiles): Record<string, unknown> => {
  const decoded: Record<string, unknown> = {};
  try {
    const save = files["savedata.dat"];
    if (save?.length === SAVEDATA_SIZE) {
      const v = new DataView(save.buffer, save.byteOffset, save.byteLength);
      const ints = (offset: number, count: number) => Array.from({ length: count }, (_, i) => v.getInt32(offset + i * 4, true));
      decoded.options = {
        volume: v.getInt32(0, true),
        vibrationEnabled: v.getInt16(4, true) !== 0,
        vibrationValue: v.getInt16(6, true),
        sync: v.getInt32(8, true),
        delay: v.getInt32(12, true),
        model: readCString(save.subarray(0x210, 0x224), "latin1"),
        planet: v.getInt32(0x224, true),
      };
      decoded.stats = {
        clearCounterA_0x2cc: v.getInt32(0x2cc, true),
        clearCounterB_0x2d0: v.getInt32(0x2d0, true),
        totalHighScore: v.getInt32(0x2e4, true),
        rankHistogram: ints(0x2e8, 6),
        comboRatioHistogram: ints(0x308, 6),
        trophies: ints(0x28c, 12),
      };
    }
    const keypad = files["keypad.dat"];
    if (keypad && keypad.length > 0) decoded.keypadFlipped = keypad[0] === 1;
    const music = files["musicdata.dat"];
    // 현재 형식: {"version":1,"records":[{"path":"res/Mus/x.mus","data":[26바이트]}]} (data = 원본 레코드의 0x62~0x7b)
    if (music && music[0] === 0x7b) {
      const state = JSON.parse(new TextDecoder().decode(music)) as { records?: { path: string; data: number[] }[] };
      const songs: Record<string, unknown> = {};
      for (const { path, data } of state.records ?? []) {
        if (!Array.isArray(data) || data.length < 0x1a) continue;
        const r = new DataView(Uint8Array.from(data).buffer);
        const ranks = [2, 4, 6, 8, 10].map(o => r.getInt16(o, true));
        songs[path] = {
          maxCombo: r.getInt16(0, true),
          highScore: r.getInt32(0x0e, true),
          rankSlots: ranks,
          bestRank: Math.min(...ranks),
          cleared: r.getInt32(0x16, true) !== 0,
        };
      }
      decoded.songs = songs;
    }
  } catch {
    // 참고용 뷰이므로 실패해도 저장 자체는 막지 않는다.
  }
  return decoded;
};

export const encodeSaveFile = (files: RawFiles, now: Date = new Date()): string => {
  const raw: Record<string, string> = {};
  for (const name of ALLOWED_FILES) {
    const data = files[name];
    if (data) raw[name] = Buffer.from(data.buffer, data.byteOffset, data.byteLength).toString("base64");
  }
  return JSON.stringify({
    schemaVersion: SCHEMA_VERSION,
    savedAt: now.toISOString(),
    note: "raw가 정본입니다. decoded는 참고용이며 수정해도 반영되지 않습니다.",
    raw,
    decoded: decodeForHumans(files),
  }, null, 2);
};

/** 유효하지 않으면 throw. 호출자는 .bak로 폴백한다. */
export const parseSaveFile = (text: string): RawFiles => {
  const json: unknown = JSON.parse(text);
  if (typeof json !== "object" || json === null) throw new Error("save_data.json: 객체가 아닙니다");
  const { schemaVersion, raw } = json as { schemaVersion?: unknown; raw?: unknown };
  if (typeof schemaVersion !== "number" || schemaVersion < 1) throw new Error("save_data.json: schemaVersion 오류");
  if (schemaVersion > SCHEMA_VERSION) throw new Error(`save_data.json: 더 새로운 버전(${schemaVersion})의 파일입니다`);
  if (typeof raw !== "object" || raw === null) throw new Error("save_data.json: raw 누락");
  const files: RawFiles = {};
  for (const name of ALLOWED_FILES) {
    const value = (raw as Record<string, unknown>)[name];
    if (value === undefined) continue;
    if (typeof value !== "string") throw new Error(`save_data.json: raw.${name} 형식 오류`);
    const buffer = Buffer.from(value, "base64");
    if (buffer.length > MAX_FILE_BYTES) throw new Error(`save_data.json: raw.${name} 용량 초과`);
    files[name] = new Uint8Array(buffer);
  }
  return files;
};

/** 렌더러에서 온 IPC 페이로드 검증. */
export const sanitizeIncoming = (payload: unknown): RawFiles => {
  if (typeof payload !== "object" || payload === null) throw new Error("잘못된 저장 요청");
  const files: RawFiles = {};
  for (const name of ALLOWED_FILES) {
    const value = (payload as Record<string, unknown>)[name];
    if (value === undefined) continue;
    if (!(value instanceof Uint8Array) || value.length > MAX_FILE_BYTES) throw new Error(`잘못된 저장 데이터: ${name}`);
    files[name] = value;
  }
  return files;
};
