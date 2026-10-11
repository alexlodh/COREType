# COREType 1.1 verification — 11 October 2026

Installed app: `/Users/alexlodh/Applications/COREType.app`  
Stable release staging: `/tmp/COREType-Release/COREType.app`  
Project: `/Users/alexlodh/Documents/Codex/2026-10-11/task/COREType`

## Automated results

- 15 dependency-free core checks; 31,836 assertions; zero failures (`tests.log`). Includes real-library integrity, scope selection, metrics, correction/Unicode, pause/resume, timed continuation, persistence, catalogue associations, book isolation, explicit other-book references, and valid local resource paths.
- 20 diagram-import integrity checks; zero failures (`diagram-verification.json`). Offline deterministic reimport, unchanged source copies, cached SHA checks, source classification, numeric/letter ranges, exact source panels, cross-book evidence, and tampering/non-self-contained SVG rejection.
- 6,893 texts exactly match the prepared pool; library SHA256 remains `cd0bb0d8cd3b4ec4443df7f4144f72c19f20130569599d8d4c2431253ccbedcb`.
- All 338 preserved import files match their original bytes. Original pool/README, source HTML, provenance and Monkeytype ZIP remain untouched in the original workspace.
- 515 diagrams / 525 original assets (517 SVG, 8 JPG), 36,263,690 asset bytes. 1,044 passages / 1,191 associations. All bundled asset hashes match the audit in both staging and installed bundles. All SVGs are self-contained.
- Installed and staging apps pass `codesign --verify --strict` with ad hoc signing. Bundle version is 1.1 (build 2).

## Native UI observations

The installed release was launched with `--ui-testing`; only `/tmp/COREType-UI-Testing/state.json` was used. Previous test state was backed up. Regular user settings/history were not used for synthetic tests.

- AppKit font inspection: Aptos absent; ArialMT and Arial-BoldMT present. Headings, controls, metrics, typing, history, settings and help now use Arial. Original textbook diagram lettering remains unchanged.
- Verified exact “Reading scope” and “Choose chapters or individual sections” labels. Both marketing taglines and both requested footer texts are absent. Dark slate theme retained; uppercase tracking and serif/rounded display typography removed.
- Unreferenced Micro U01 S01 P001 has no figure button. Micro U01 S01 P006 exposes Figure 1.1, whose local SVG rendered sharply with the exact source caption and credits. Zoom changed to 150%; Fit restored 100%; full credits/licence are accessible by scrolling.
- Opening a figure during typing pauses the engine. Cmd-P and Cmd-N do not resume/advance while the figure sheet is open. Closing keeps the test paused; Resume restores the same input. Wrong characters show red/underline; correcting them retains mistake statistics. The 466-character passage then completed with 466 retained correct characters, two corrections and zero remaining errors.
- History showed the completed result. Its replay control returned to the exact starting passage with zeroed metrics and the correct scope/figure.
- Native Export CSV save panel wrote `/tmp/COREType-UI-Verified-history.csv`. Parsed one row / 15 columns; passage ID, elapsed time, WPM, accuracy, mistakes and corrections match persisted values (`ui-export-check.json`). Synthetic speed values are not human performance evidence.
- A 60-second timed test completed the figure-referencing paragraph and advanced to Micro U01 S01 P007. The figure button disappeared, input reset for the next paragraph, and accumulated metrics/timer continued.
- Macro U10 S02 P030 displayed two source-proven figures. The menu correctly switched Macroeconomics Figure 10.2 to explicitly referenced Microeconomics Figure 1.1, with the correct image/caption/book label.
- Micro U08 S04 P007 displayed the original Figure 8.8 panels. Next panel changed from feasible set to producer surplus; next/previous controls correctly disabled at the endpoints.
- Settings and attribution/help sheets were visually checked. `practice-ui.png`, `figure-viewer.png`, `multi-panel-figure.png` and `settings.png` record selected views.

## Limits

Only this Apple Silicon Mac/macOS release was tested. The app is ad hoc signed; it is not Developer ID signed or notarized. Do not bypass any macOS security warning.

The catalogue includes explicit numeric references from the prepared passages. HTML-only table figures, photographs/document illustrations and the secondary satellite image are intentionally excluded. Slideshow figures use unchanged original static summary images; two explicitly referenced source panels are retained. General phrases such as “the figure above” are not assigned by guesswork. Original prepared paragraph splits and occasional LaTeX/math notation remain. All original caption/source text is preserved; it is not rewritten for the interface.

Native visual inspection sampled the cases above; it did not manually open all 515 diagrams. Every bundled asset was checked structurally and by hash, and all eight selected JPG assets were visually inspected during catalogue preparation. The app was not tested on another machine.
