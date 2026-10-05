/** Fixed VRP identity follows the original bytes; MUS picture slices are unregistered. */
const fixedVrps = new WeakMap<Uint8Array, string>();

export function registerFixedVrp(bytes: Uint8Array, path: string): void {
  const normalized = path.replaceAll('\\', '/');
  if (/^res\/Vrp\/[^/]+\.vrp$/i.test(normalized)) fixedVrps.set(bytes, normalized.slice('res/Vrp/'.length));
}

export function fixedVrpName(bytes: Uint8Array): string | undefined { return fixedVrps.get(bytes); }
