# COREType 1.2 verification — 11 October 2026

Installed app: `/Users/alexlodh/Applications/COREType.app`  
Stable release staging: `/tmp/COREType-Release/COREType.app`  
Project: `/Users/alexlodh/Documents/Codex/2026-10-11/task/COREType`

## Automated results

- 17 dependency-free core checks; 34,545 assertions; zero failures (`tests.log`). Includes the existing typing, scope, metrics and persistence checks, figure matching/book isolation, older catalogue decoding, figure/table number namespaces, local kind/path/extension validation, symlink rejection and actual source table cells/headers/spans.
- 14 table integrity checks; zero failures (`table-verification.json`, `table-checks.log`). All 128 panels compared against actual saved source. Sanitizer checks cover spans, alignment, inline formatting, inert links, MathML/TeX preservation and removal of active or remote content. Re-run with `python3 scripts/import_diagrams.py import-source --verify-tables`.
- An independent BeautifulSoup comparison checked all 128 assets across 59 saved source pages: 779 rows, 3,608 ordered cells, 109 spanning cells, 429 inline formatting elements and 12 source links. Zero mismatches in cell tags/text, spans, rows, formatting, explanatory step text or hashes (`table-source-comparison.json`). Re-run with `python3 verification/table-source-compare.py`; this optional verifier needs BeautifulSoup 4. The app/importer/core checks have no such dependency.
- Two offline imports produced the same catalogue SHA256, `faa5c7db4b7bc0ae494866d7b45b30d7a31361b31971811861ecfa695f83e022`. Existing diagram integrity evidence is retained in `diagram-verification.json`.
- All 6,893 texts exactly match the prepared pool; library SHA256 remains `cd0bb0d8cd3b4ec4443df7f4144f72c19f20130569599d8d4c2431253ccbedcb`.
- All 338 preserved import files and original workspace files match their original bytes, including the Monkeytype setup ZIP.
- 585 source figures: 515 image diagrams plus 70 table-only figures. Tables also appear within 17 image figures. Resources include 525 unchanged original images (517 SVG, 8 JPG) and 128 table panels; 36,424,330 asset bytes. There are 1,140 mapped passages / 1,315 associations; 164 passages have tables. All 1,044 prior image-passage mappings remain present.
- Every source resource matches the staging and installed bundle. Both pass `codesign --verify --strict` with ad hoc signing. Version 1.2, build 3 (`release-validation.json`).
- Twelve superseded local COREType bundles, ZIPs and deliverable files were moved to recoverable macOS Trash (`cleanup.json`). Original imports, normal app data and Git history were retained.

## Native 1.2 UI observations

Synthetic input used only `--ui-testing` and `/tmp/COREType-UI-Testing/state.json`. The normal profile's SHA256 was identical before and after these checks. The normal app was reopened afterwards.

- Micro U01 S06 P008 exposes **Figure 1.8a · Table**. Its original three headers and grain-production cells rendered in aligned columns. The 16-row table scrolls to its final 3,000 / 946,000 / 315 row. Zoom reached 150%; horizontal scrolling exposed the rightmost values. `table-viewer.png` records the initial view.
- Opening that table after typing three correct characters pauses the test. Cmd-P and Cmd-N do not resume or advance while the sheet is open. Done leaves the same paragraph paused at 3 / 235 characters. Resume and typing the remainder completed with 235 correct characters and no errors.
- Micro U08 S03 P008 displays Figure 8.5 with the original two row-spanning market descriptions. The four-column text layout fits and wraps legibly; the spans align with their two buyer/seller rows (`table-spans.png`).
- Macro U06 S02 P017 exposes three table figures (6.3a/c/e). Figure 6.3a's source before/after panels switch correctly; Previous/Next disable at endpoints. The after-loan panel preserves 50 grain, a 50 loan to Julia, 100 total assets, zero liabilities and the original explanatory text, accessible by scrolling (`table-panels.png`).
- Macro U06 S04 P017 switches 6.8a to 6.8c through the source figure menu. The 11-row, ten-column balance sheet preserves group headings, column spans, values and scroll bars (`wide-table.png`).
- Micro U02 S04 P011 displays the unchanged Figure 2.4 SVG, then its matching original five-column input table through Next panel. Previous panel restores the SVG. Table zoom reached 150%; Fit restored 100%. Source captions/credits remain visible (`figure-viewer.png`, `mixed-table-panel.png`).
- The clean practice interface retains **Reading scope**, **Choose chapters or individual sections**, Arial typography, the dark slate theme and the removed marketing/footer copy (`practice-ui.png`). Help copy now describes figures and tables, zoom, scrolling and panel controls.

## Previously verified native behavior

These observations were made on 1.1 and remain documented as prior checks; they were not all repeated for the table-only change:

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

Only this Apple Silicon Mac/macOS 26.6.2 was tested. The app is ad hoc signed, not Developer ID signed or notarized. Other machines/macOS versions remain untested; do not bypass a macOS warning.

The catalogue uses explicit source-qualified figure numbers. No numbered Table captions were found in the saved textbook HTML: table content is mostly numbered as Figure in the books, and the UI retains those numbers. One passage's external ONS “Table 2” has no saved corresponding table and remains unavailable. Photographs, decorative document illustrations, cover images and the secondary satellite image remain excluded. General phrases such as “the figure above” are not assigned by guesswork.

Three table panels retain literal LaTeX already present in the saved source. Native mathematical markup and inline sub/superscripts are preserved; no MathJax, scripts or remote resources are fetched. Original prepared paragraph splits and occasional LaTeX in passages remain. No source cells, captions or credits are rewritten.

Native visual inspection sampled the cases above; it did not manually open all 585 figures or 128 table panels. Every bundled asset was checked structurally and by hash, all table panels were independently compared to source, and all eight selected JPG images were visually inspected during earlier catalogue preparation. Synthetic typing verifies behavior, not human performance.
