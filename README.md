# COREType 1.4.2

Version 1.4.2 adds Previous paragraph navigation. It remembers the path through both ordered and random selections, so Next moves forward again after going back. Version 1.4.1 enlarged the clickable area of the top-right Practice, History and Settings buttons.

A standalone, native, offline macOS typing app using Sasha's existing prepared **The Economy 2.0** excerpts. It includes 6,893 paragraphs: 3,505 Microeconomics and 3,388 Macroeconomics, organized into 20 verified chapters and 271 sections. No account, browser, network service, or third-party runtime is required.

## Launch

Open `/Users/alexlodh/Applications/COREType.app` in Finder, or unzip `COREType-macOS.zip` and open the app. The verified build staging location is `/tmp/COREType-Release/COREType.app`. The bundle is built for Apple Silicon and declares macOS 14 or later. The actual release is tested on macOS 26.6.2, Apple Silicon; other systems are untested. You may copy the bundle wherever you keep your apps. The locally built bundle is ad hoc signed, not Developer ID signed or notarized. Do not change security settings or bypass a macOS warning; if a warning appears on another machine, stop and report it.

## Practice

- Browse Both, Micro, or Macro; search chapter and section titles by topic or number. The book tabs and search filter the browser. Checkboxes define the scope, and **Use this selection** applies it.
- Select a whole unit with its checkbox, or expand it to choose individual sections. **Select shown** and **Clear shown** affect the visible search results only. Empty scopes display a recovery prompt.
- **In order** follows Micro, then Macro, with unit/section/paragraph order preserved and wraparound. **Random** draws a whole paragraph from the applied scope and avoids immediate repeats when the scope has multiple paragraphs. Previous and Next let you revisit the navigation path in either mode. No words are shuffled.
- **Passage** completes after the entire excerpt. **Timed** starts on the first typed character and continues through complete paragraphs until the active timer expires. Presets are 15, 30, 60, and 120 seconds; custom duration accepts 1–3,600 seconds.
- Click the passage to focus it. Correct characters brighten, errors turn red with an underline, and the amber caret follows your typing. Long passages scroll to the caret.
- Backspace corrects a character; Option–Backspace deletes back to the preceding space. Mistakes remain counted after correction. Text is typed sequentially; arrow keys do not move the input position. Paste is disabled.
- Escape or Command–P pauses/resumes. Leaving the app pauses a running test. History navigation and modal settings pause it too. Command–T focuses the passage.
- Command–R repeats the starting paragraph with fresh statistics. Command–N chooses the next paragraph. Return after completion advances. Command–1 and Command–2 switch practice/history.
- History keeps completed and interrupted tests separately; its averages use completed tests only. A replay button practices the original starting paragraph and selects its section. Export CSV includes detailed metrics.

## Interface and textbook figures and tables

COREType uses Arial for headings, controls, metrics, help and typing text, with the platform font fallback if needed. Arial is installed on the tested Mac; Aptos is not. The dark slate palette is retained. Marketing taglines, tracked uppercase labels and redundant practice/footer text have been removed.

Relevant original textbook diagrams and tables appear automatically directly after the passage, inside the same typing area and vertical scroll. Their captions, source credits and book names follow the source material. **Settings → Show textbook figures and tables** turns this on or off; it is enabled by default and saved on this Mac. Changing the setting preserves the current passage, input and statistics. Figures and tables are reading context and are excluded from the typing target and metrics. The passage remains available while paused, so the source material can be read without running the timer. Wide tables scroll horizontally.

The catalogue contains **585 source figures**: **515 diagrams / 525 original images**, plus 70 table-only figures. It bundles **95 original table assets across 87 figures**, including 17 figures with both images and tables. It supports **1,140 passages / 1,315 figure associations**; 164 passages reference figures containing tables. Eight cross-book references have explicit source evidence. The catalogue is separate from the unchanged paragraph library. Associations use qualified book/figure identifiers and actual source containers; explicit references to the other book are recorded separately. Numbered photographs, document illustrations, cover images and unreferenced images are excluded. Image slides use the complete original summary image or an explicitly referenced source image. Repeated instructional table steps use the source-authored static summary. The leverage example uses its complete final source table, and distinct before/after or exercise/answer tables remain. No replacement diagrams, rewritten table cells or rewritten captions are generated.

SVG, raster files and sanitized source table HTML are bundled locally. The inline renderer uses macOS WebKit through a private local image scheme. Source JavaScript and remote navigation are disabled; a fixed app-owned query measures document height in an isolated client world. The app does not fetch figures, tables, fonts or scripts at runtime. Figure import is a build-time task and downloads missing original assets from CORE Econ; cached assets are hash-verified. Tables preserve the original cells, headers, row/column spans, mathematical markup and alignment. Textbook resources keep their own attribution and CC BY-NC-ND terms.

Five retained tables contain literal source LaTeX: Macro 7.6 and Micro 7.10, 7.11, 7.12 and 7.16. It remains visible as source notation. One reference to an external ONS Table 2 has no corresponding saved table and remains unavailable. Micro Figure 3.22's static summary lists household paid work as 10, while its animation steps list 12; the original static summary is retained unchanged and the discrepancy is audited. General phrases such as “the figure above” are not assigned by guesswork.

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

For isolated UI testing, launch with `--ui-testing`; data goes to `/tmp/COREType-UI-Testing/state.json` and does not touch the regular profile. Adding `--fixture "CORE Micro U01 S06 P008"` starts that exact library passage and its section. The fixture argument is accepted only with `--ui-testing`.

## Build and verify

Requires Apple's Swift Command Line Tools and macOS. No package downloads are needed. From this directory:

```sh
bash scripts/test.sh
CORETYPE_APP_OUTPUT=/tmp/COREType-Release/COREType.app bash scripts/build-app.sh
open /tmp/COREType-Release/COREType.app
```

`scripts/swift-env.sh` keeps compiler and SwiftPM caches inside `.build` for restricted workspaces. Its `--disable-sandbox` flag disables the nested Swift package build-process sandbox; it does not change macOS security settings. The native SwiftPM backend is retained because the newer backend encountered build sandbox issues on this toolchain. The build script compiles release code, generates the native icon, assembles a fresh complete bundle under `/tmp`, applies an ad hoc local signature, and verifies that signature before replacing the output. A previous output is moved to Trash only after its bundle identifier is verified as COREType; unrelated files, apps and symlinks are rejected. Exact Trash moves are recorded under `work/`. Fresh assembly prevents removed resources from surviving in a rebuilt app.

Build bundles under `/tmp`: this synced workspace can acquire FinderInfo metadata after signing. Copy the completed bundle into Applications and verify there with `codesign --verify --strict`. Do not alter quarantine or security settings.

The dependency-free `CoreChecks` executable runs the test suite without XCTest, which is absent from this Mac's Command Line Tools. Tests cover exact metrics, corrected and uncorrected errors, deadline completion, pause/resume, timed paragraph continuation, punctuation, Unicode/backspace, repeats, complete long passages, the actual 6,893-paragraph library, chapter search/filtering, ordered/random/empty/singleton scopes, atomic settings/history persistence, migration and saved opt-out for inline media, source-proven figure matching, book isolation/explicit cross-book references, local image/table paths, schema compatibility, and source table cells/headers/spans. Version 1.4 adds randomized differential checks for incremental metrics, Unicode UTF-16 render ranges, repeated targets and exact deadlines, plus deterministic cosmetic-timer lifecycle checks.

## CPU optimization

Version 1.4 isolates tenths-of-a-second metric updates from the typing document and sidebar. The cosmetic timer runs only during visible, focused, active practice; ready, paused, finished, history and background states stop it. Timed completion uses a separate monotonic deadline and rejects input or deletion after expiry, even if a callback is delayed. Caret blinking is similarly conditional and invalidates its own rectangle.

The typing document builds the attributed source passage once per passage/font change, then updates the affected character ranges. Its UTF-16 mapping preserves grapheme counts, wrong glyphs, punctuation equivalence and corrections, including emoji and combining characters. Geometry updates occur when document or viewport geometry changes. Scope counts, search results, chapter section sets, source figures and history aggregates are cached at their change boundaries. Inline WebKit creation is deferred until enabled source material exists, while the original SVGs, tables, captions, credits and shared scrolling remain.

The measured comparison, native regressions and limits are recorded in [verification/CPU-Optimization.md](verification/CPU-Optimization.md). Three native 30-second runs typing the same 144 characters at a target five characters/second reduce median main-process CPU from 1.165% to 0.454% on this Mac. Three 30-second runs of the isolated, media-disabled AppKit renderer reduce median CPU from 1.640% to 0.552% and full attributed rebuilds from 453 to 3 across three fresh documents and 450 input events. Explicit layout requests fall from 906 to 33. These renderer measurements exclude native drawing, SwiftUI and WebKit-helper CPU; native process comparisons are reported separately. Renderer correctness passes 58,428 actual NSTextStorage display/attribute/caret assertions, including Unicode wrong-glyph range changes. Matched paused/finished/history CPU baselines, the additional native media/resize CPU matrix, cold-load timing, end-to-end input latency and native timer/body counters were not measured; the report distinguishes functional coverage and isolated renderer results from native CPU claims. Developer diagnostics are opt-in: `--performance-report /tmp/coretype-counters.json` collects counters and flushes them at save, pause, navigation and quit transitions. Normal launches collect no counters or diagnostic files. `scripts/measure-process.py` measures an explicitly selected COREType PID using monotonic elapsed time and cumulative macOS process CPU; 100% means one logical core. Sampling runs remain separate from steady CPU measurements.

Implementation:

- `Sources/TypingCore`: pure Swift engine, library/scope selection, and Codable persistence.
- `Sources/COREType`: SwiftUI interface, shared appearance, AppKit typing document and offline inline textbook renderer.
- `Tests/TypingCoreTests`: repeatable core checks.
- `scripts`: import, test, icon, and bundle build tools.
- `verification`: build/test logs, source, diagram and table audits, and observed UI verification notes.
- `import-source`: preserved inputs for reproducible import, including the original Monkeytype setup.

The SDK on this Mac includes a new SwiftUI `@State` macro whose plugin is supplied only by Xcode. `ViewState` aliases the standard `SwiftUI.State` property wrapper to build with Command Line Tools without that plugin.

## Verification and release

Version 1.4 retains the inline textbook context and saved display setting introduced in 1.3 while reducing unnecessary clock observation, text reconstruction, layout and inactive timers. It passed **25 core checks / 253,258 assertions**, with zero failures. The source-table verifier again passed **18 table integrity checks** for all **95 assets**. The preserved independent source comparison covers **2,663 cells**. Library and catalogue hashes remain equal to the audited 1.3 release; all 525 original images, passage associations, captions, credits and paragraph texts remain unchanged. All 338 listed preserved import files also match the original SHA256 manifest. Current performance and release verification are recorded in [verification/CPU-Optimization.md](verification/CPU-Optimization.md).

The preserved 1.3 native UI observations are recorded in `verification/UI-Verification.md`. Earlier checks also exercised typography/copy, corrected typing and completion, timed advancement, history replay and the native CSV save panel; exported values matched the saved test result. `verification/Code-Cleanup.md` describes the 1.3 inline-media cleanup, preserved behavior and remaining implementation constraints.

`verification/UI-Verification.md` describes the tested cases and limitations; screenshots and machine-readable audits are alongside it. All UI tests used the isolated testing profile. Synthetic typing verifies behavior, not human speed.

The private GitHub repository, [alexlodh/COREType](https://github.com/alexlodh/COREType), includes the source, bundled figures and tables, preserved imports, tests, attribution and verification. The verified app ZIP is also tracked in `distribution/COREType-macOS.zip`. Local deliverable ZIPs contain the signed Apple Silicon app and a portable source snapshot. Build caches and personal settings/history are excluded.

## Source integrity and attribution

The importer reads the richer prepared saved-text library, per-paragraph provenance, book manifest, and saved source HTML. It checks every name against its actual source-page section number and obtains chapter titles from the source `<h1>`. It compares all imported texts, in order, to the prepared random pool before writing. `Sources/COREType/Resources/Source-Audit.json` records counts and hashes; it reports zero unmapped paragraphs and zero mismatched sections.

To regenerate from the existing source workspace (read-only):

```sh
python3 scripts/import_library.py import-source
```

Figure and table import from preserved source pages (network only for missing build-time originals):

```sh
python3 scripts/import_diagrams.py import-source
python3 scripts/import_diagrams.py import-source --offline
python3 scripts/import_diagrams.py import-source --verify-tables
```

`--offline` never fetches. It requires all cached assets and verifies their stored source URLs and SHA256 hashes before rebuilding the catalogue. `verification/diagram-audit.json` contains source HTML hashes, exact figure matches, classification evidence, asset hashes, table cell/span integrity, excluded references and credits.

The table audit records the original summary classes, completed leverage-frame evidence and the Figure 3.22 source discrepancy. Import removes superseded generated table HTML recoverably, only when its previous audit hash matches and no selected figure references it. The independent optional comparison can be rerun with `python3 verification/table-source-compare.py`; it requires BeautifulSoup 4, while the importer, app and core checks have no external package dependencies.

The original Monkeytype setup ZIP and source workspace remain untouched. Superseded COREType application bundles and deliverable ZIPs are moved to Trash when replaced; the current release uses the same stable filenames. Git history remains available. `import-source/` preserves the original prepared pool, saved-text library, metadata/provenance, source HTML, README, and `CORE-Random-Paragraphs-Setup.zip`. `verification/preserved-import-hashes.json` records their exact bytes for reproducibility. This is the prepared excerpt collection, not the complete textbooks. Front matter, glossaries, references, and equation-heavy material are excluded; some short plain-text LaTeX notation and exercise/extension prose remain. Some long original paragraphs were already split during preparation. No new shortening, splitting, paraphrasing, or punctuation rewriting is performed by this app.

Book attribution and CC BY-NC-ND 4.0 terms are preserved in `Attribution.txt`, available inside the app's Credits & help dialog, and in the exact `Original-Import-README.txt`. Use the textbook excerpts for noncommercial practice. No CORE Econ or Monkeytype endorsement is implied.
