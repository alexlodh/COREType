# COREType

A standalone, native, offline macOS typing app using Sasha's existing prepared **The Economy 2.0** excerpts. It includes 6,893 paragraphs: 3,505 Microeconomics and 3,388 Macroeconomics, organized into 20 verified chapters and 271 sections. No account, browser, network service, or third-party runtime is required.

## Launch

Open `/Users/alexlodh/Applications/COREType.app` in Finder, or unzip `COREType-macOS.zip` and open the app. A refreshed copy is also kept in `dist/COREType.app`. The bundle is built for Apple Silicon and declares macOS 14 or later. The actual release is tested on the current Apple Silicon Mac; other macOS releases are not tested. You may copy the bundle wherever you keep your apps. The locally built bundle is ad hoc signed, not Developer ID signed or notarized. Do not change security settings or bypass a macOS warning; if a warning appears on another machine, stop and report it.

## Practice

- Browse Both, Micro, or Macro; search chapter and section titles by topic or number. The book tabs and search filter the browser. Checkboxes define the scope, and **Use this selection** applies it.
- Select a whole unit with its checkbox, or expand it to choose individual sections. **Select shown** and **Clear shown** affect the visible search results only. Empty scopes display a recovery prompt.
- **In order** follows Micro, then Macro, with unit/section/paragraph order preserved and wraparound. **Random** draws a whole paragraph from the applied scope and avoids immediate repeats when the scope has multiple paragraphs. No words are shuffled.
- **Passage** completes after the entire excerpt. **Timed** starts on the first typed character and continues through complete paragraphs until the active timer expires. Presets are 15, 30, 60, and 120 seconds; custom duration accepts 1–3,600 seconds.
- Click the passage to focus it. Correct characters brighten, errors turn red with an underline, and the amber caret follows your typing. Long passages scroll to the caret.
- Backspace corrects a character; Option–Backspace deletes back to the preceding space. Mistakes remain counted after correction. Text is typed sequentially; arrow keys do not move the input position. Paste is disabled.
- Escape or Command–P pauses/resumes. Leaving the app pauses a running test. History navigation and modal settings pause it too. Command–T focuses the passage.
- Command–R repeats the starting paragraph with fresh statistics. Command–N chooses the next paragraph. Return after completion advances. Command–1 and Command–2 switch practice/history.
- History keeps completed and interrupted tests separately; its averages use completed tests only. A replay button practices the original starting paragraph and selects its section. Export CSV includes detailed metrics.

## Interface and textbook diagrams

COREType uses Arial for headings, controls, metrics, help and typing text, with the platform font fallback if needed. Arial is installed on the tested Mac; Aptos is not. The dark slate palette is retained. Marketing taglines, tracked uppercase labels and redundant practice/footer text have been removed.

A **Figure** or **Figures** button appears in the passage header only for diagrams explicitly referenced in that prepared excerpt. Opening it pauses a running test. The viewer shows the original diagram, caption, source credits and book name. Use the figure menu to switch diagrams, **+ / −** to zoom, **Fit** to restore the full view, and **Done** to return. Resume a paused test explicitly.

The catalogue bundles **515 diagrams / 525 original image assets** and supports **1,044 passages / 1,191 figure associations**, including eight source-proven cross-book references. The catalogue is separate from the unchanged paragraph library. Associations use qualified book/figure identifiers and actual source containers; explicit references to the other book are recorded separately. Numbered photographs, document illustrations, cover images, unreferenced images and table-only containers are excluded. For source slide sequences the complete original summary image is used; explicitly referenced subfigures retain their original panel. No replacement diagrams or rewritten captions are generated.

SVG and raster files are bundled locally. The viewer uses macOS WebKit to display original files through a private local scheme, disables JavaScript, blocks remote navigation, and restricts image loading to that local scheme. The app does not fetch diagrams, fonts or scripts at runtime. Diagram import is a build-time task and downloads missing original assets from CORE Econ; cached assets are hash-verified. Textbook resources keep their own attribution and CC BY-NC-ND terms.

## Metric definitions

Five characters count as one standard word, including spaces and punctuation. Paused time is excluded.

| Metric | Definition |
| --- | --- |
| WPM | Retained correct characters ÷ 5 ÷ active minutes |
| Raw WPM | All typed character attempts ÷ 5 ÷ active minutes, including retyped characters |
| Accuracy | Correct character attempts ÷ all character attempts × 100 |
| Error rate | Incorrect character attempts ÷ all character attempts × 100 |
| Mistakes | Incorrect character attempts, including those later corrected |
| Corrections | Incorrect characters removed with Backspace |
| Remaining errors | Wrong characters still in the typed text, including completed timed paragraphs |

Backspace does not count as a character attempt. WPM can be lower than raw speed after corrections. Completing the final character ends a passage test, even if it is incorrect. Completed timed paragraphs cannot be backspaced into; their statistics remain accumulated. Extremely short tests can produce unstable speed estimates. These definitions are explicit and do not claim exact numerical parity with every Monkeytype mode.

Keyboard punctuation matching accepts straight/curly quotes and hyphen/en/em dash equivalence by default. It changes matching only, never the saved excerpt. Strict matching is available in Settings. Ellipses and mathematical symbols still require exact characters. The imported pool already had Monkeytype's documented typography normalization, preserved unchanged here.

## Local data

Settings and up to 1,000 recent results are written atomically to:

`~/Library/Application Support/COREType/state.json`

No user data leaves the Mac. Source excerpts are bundled read-only and do not depend on the old workspace at runtime. Unreadable state is copied to a timestamped backup before recovery; write failures are displayed. In-progress text is not restored after quitting, but attempted sessions are recorded as interrupted. The app does not read or modify Monkeytype's browser storage.

For isolated UI testing, launch with `--ui-testing`; data goes to `/tmp/COREType-UI-Testing/state.json` and does not touch the regular profile.

## Build and verify

Requires Apple's Swift Command Line Tools and macOS. No package downloads are needed. From this directory:

```sh
bash scripts/test.sh
CORETYPE_APP_OUTPUT=/tmp/COREType-Release/COREType.app bash scripts/build-app.sh
open /tmp/COREType-Release/COREType.app
```

`scripts/swift-env.sh` keeps compiler and SwiftPM caches inside `.build` for restricted workspaces. Its `--disable-sandbox` flag disables the nested Swift package build-process sandbox; it does not change macOS security settings. The build script compiles release code, generates the native icon, assembles resources/Info.plist, applies an ad hoc local signature, and verifies that signature.

Build bundles under `/tmp`: this synced workspace can acquire FinderInfo metadata after signing. Copy the completed bundle into Applications and verify there with `codesign --verify --strict`. Do not alter quarantine or security settings.

The dependency-free `CoreChecks` executable runs the test suite without XCTest, which is absent from this Mac's Command Line Tools. Tests cover exact metrics, corrected and uncorrected errors, deadline completion, pause/resume, timed paragraph continuation, punctuation, Unicode/backspace, repeats, complete long passages, the actual 6,893-paragraph library, chapter search/filtering, ordered/random/empty/singleton scopes, atomic settings/history persistence, source-proven figure matching, book isolation/explicit cross-book references, and local diagram assets.

Implementation:

- `Sources/TypingCore`: pure Swift engine, library/scope selection, and Codable persistence.
- `Sources/COREType`: SwiftUI interface and AppKit keyboard/caret/scroll surface.
- `Tests/TypingCoreTests`: repeatable core checks.
- `scripts`: import, test, icon, and bundle build tools.
- `verification`: build/test logs, source and diagram audits, and observed UI verification notes.
- `import-source`: preserved inputs for reproducible import, including the original Monkeytype setup.

The SDK on this Mac includes a new SwiftUI `@State` macro whose plugin is supplied only by Xcode. `ViewState` aliases the standard `SwiftUI.State` property wrapper to build with Command Line Tools without that plugin.

## Verification and release

Version 1.1 passed 15 core checks / 31,836 assertions with zero failures. The diagram importer passed 20 additional integrity checks and an offline deterministic rerun. Native UI checks exercised the updated typography/copy, SVG viewing and zoom, source credits, multiple panels, qualified cross-book figure switching, pause/resume, corrected typing and completion, timed advancement with figure controls updating, history replay, and the native CSV save panel. Exported values were checked against the saved test result.

`verification/UI-Verification.md` describes the tested cases and limitations; screenshots and machine-readable audits are alongside it. All UI tests used the isolated testing profile. Synthetic typing verifies behavior, not human speed.

The private GitHub repository, [alexlodh/COREType](https://github.com/alexlodh/COREType), includes the source, bundled diagrams, preserved imports, tests, attribution and verification. The verified app ZIP is also tracked in `distribution/COREType-macOS.zip`. Local deliverable ZIPs contain the signed Apple Silicon app and a portable source snapshot. Build caches and personal settings/history are excluded.

## Source integrity and attribution

The importer reads the richer prepared saved-text library, per-paragraph provenance, book manifest, and saved source HTML. It checks every name against its actual source-page section number and obtains chapter titles from the source `<h1>`. It compares all imported texts, in order, to the prepared random pool before writing. `Sources/COREType/Resources/Source-Audit.json` records counts and hashes; it reports zero unmapped paragraphs and zero mismatched sections.

To regenerate from the existing source workspace (read-only):

```sh
python3 scripts/import_library.py import-source
```

Diagram import from preserved source pages (network only for missing build-time originals):

```sh
python3 scripts/import_diagrams.py import-source
python3 scripts/import_diagrams.py import-source --offline
```

`--offline` never fetches. It requires all cached assets and verifies their stored source URLs and SHA256 hashes before rebuilding the catalogue. `verification/diagram-audit.json` contains source HTML hashes, exact figure matches, classification evidence, asset hashes, excluded references and credits.

The existing Monkeytype setup, ZIP files, and original source workspace remain untouched. `import-source/` preserves the original prepared pool, saved-text library, metadata/provenance, source HTML, README, and `CORE-Random-Paragraphs-Setup.zip`. `verification/preserved-import-hashes.json` records their exact bytes for reproducibility. This is the prepared excerpt collection, not the complete textbooks. Front matter, glossaries, references, and equation-heavy material are excluded; some short plain-text LaTeX notation and exercise/extension prose remain. Some long original paragraphs were already split during preparation. No new shortening, splitting, paraphrasing, or punctuation rewriting is performed by this app.

Book attribution and CC BY-NC-ND 4.0 terms are preserved in `Attribution.txt`, available inside the app's Credits & help dialog, and in the exact `Original-Import-README.txt`. Use the textbook excerpts for noncommercial practice. No CORE Econ or Monkeytype endorsement is implied.
