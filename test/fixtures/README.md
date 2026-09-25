# Reference fixtures

These compressed fixtures preserve outputs captured from the original
`rhythmstar-web` TypeScript implementation when the Dart port was validated.
They are test data, not executable code or app assets.

- `dart-runtime.json.gz`: inputs, state transitions, audio/storage commands and
  exact RGB565 pixels for 59 reference screens.
- `dart-logic.json.gz`: 128 compiled charts, 14 complete sessions, scoring and
  timing expectations.
- `render-parity.json.gz`: original draw commands and reference pixels for the
  software renderer.

`flutter test` reads these files directly, independently of TypeScript or Node.
The Node-based generation scripts have been removed. App resources,
pre-rendered audio and Dart constants are maintained directly in this project.
Do not overwrite expectations with outputs from the implementation under test.
