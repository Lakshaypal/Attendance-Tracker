# OCR fixture

Regenerates `test/fixtures/vision_timetable_words.json`, the recorded output of a real text recogniser used by `test/vision_fixture_test.dart`.

The synthetic tests in `test/timetable_parser_test.dart` build perfect word boxes and prove the parsing algorithm. This fixture proves the parser survives what an actual recogniser returns: a page heading above the grid, a Unicode homoglyph, and a genuine misread.

## Regenerate (macOS)

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --hide-scrollbars --window-size=1100,520 --screenshot=timetable.png "file://$PWD/tool/ocr_fixture/timetable.html"
```

```bash
swiftc -O tool/ocr_fixture/ocr_dump.swift -o /tmp/ocr_dump && /tmp/ocr_dump timetable.png > test/fixtures/vision_timetable_words.json
```

`ocr_dump.swift` mirrors the Vision request in `macos/Runner/MainFlutterWindow.swift` exactly — same recognition level, same `usesLanguageCorrection = false`, same normalised top-left boxes — so the recorded words are what the app itself would receive.

Vision output is not bit-stable across OS versions. If regenerating changes which cells are misread, update the assertions in `vision_fixture_test.dart` to match the new reality rather than forcing the old one.
