# COREType 1.3 verification — 11 October 2026

Installed app: `/Users/alexlodh/Applications/COREType.app`  
Stable release staging: `/tmp/COREType-Release/COREType.app`  
Project: `/Users/alexlodh/Documents/Codex/2026-10-11/task/COREType`

## Automated results

- 18 dependency-free core checks; 34,263 assertions; zero failures (`tests.log`). Covers typing metrics, corrections, Unicode/backspace, punctuation, timers, scope/order/random selection, history/persistence, source-proven figure matching, explicit cross-book exceptions, resource validation and original table cells/spans. The new preference migration check preserves all earlier settings and history, defaults missing media visibility to true, persists opt-out and rejects malformed values.
- 18 source-table checks; zero failures (`table-verification.json`, `table-checks.log`). Sanitizer and source-selection checks cover spans, alignment, formatting, inert links, MathML/TeX preservation, removal of active content, original static summaries, complete final-frame selection and obsolete asset pruning.
- Independent BeautifulSoup comparison: 95 assets on 59 saved source pages, 618 rows, 2,663 ordered cells, 96 spanning cells, 361 inline formatting elements and 12 inert links. No text, tag, span, formatting, explanatory-text or hash mismatches (`table-source-comparison.json`). Re-run with `python3 verification/table-source-compare.py`; this optional verifier needs BeautifulSoup 4. App/importer/core checks have no third-party dependency.
- Two offline imports produced catalogue SHA256 `0e7cd966cdd835de9c856fca6c3c20e2ba4357b67fc346f57cbe6f5c9c90b3e8`.
- All 6,893 prepared texts remain exact; library SHA256 `cd0bb0d8cd3b4ec4443df7f4144f72c19f20130569599d8d4c2431253ccbedcb`. There are 3,505 Microeconomics and 3,388 Macroeconomics passages, 20 chapters and 271 sections.
- All 338 preserved inputs and original source workspace files retain their recorded bytes, including the Monkeytype setup ZIP.
- 585 source figures: 515 diagrams and 70 table-only figures; 17 diagram figures also contain tables. Resources contain all 525 original images and 95 table assets (36,386,606 bytes). All 1,140 mapped passages / 1,315 associations, captions and credits are preserved; 164 passages reference tables.
- Strict ad hoc signatures and source-resource equality are checked for staging, installed and ZIP-extracted bundles (`release-validation.json`). Version 1.3, build 4.
- Superseded generated table files, application bundles, packages and viewer screenshots were moved to recoverable Trash (`cleanup.json`). Original source, normal app state and Git history are retained.

## Native 1.3 UI observations

Synthetic input used only `--ui-testing` and `/tmp/COREType-UI-Testing/state.json`. Normal-profile bytes are checked before and after the test run. Synthetic speeds are functional evidence, not human performance. The normal app is reopened after checks.

- Micro U01 S06 P008 automatically places Figure 1.8a's three-column table directly below the 235-character passage in the typing area. There is no figure button, sheet, item picker, zoom toolbar or panel navigation (`inline-table.png`).
- Vertical scrolling over the table moves the same document from the paragraph to the final 3,000 / 946,000 / 315 row, original caption, source URL and licence (`inline-table-source.png`). The first character starts the timer; reading/scrolling source material does not pause it. Timer updates leave the source scroll position intact.
- Clicking a source table, typing a wrong character, correcting with Backspace and continuing returns to the active caret. Mistakes remain counted. Command–P pauses; the passage and source remain readable, with an explicit Resume control (`inline-paused.png`).
- Settings includes **Show textbook figures and tables** (`inline-settings.png`). Turning it off removes source material while preserving the same paragraph, 4 typed characters, accuracy/mistake counts and paused state (`inline-disabled.png`). After quitting and relaunching, Settings remains unchecked and history is retained. Turning it back on restores the source material. Completing the 235-character passage records a result with 235 retained correct characters and zero remaining errors.
- Micro U02 S04 P011 renders original Figure 2.4's SVG and matching five-column olive-oil input table successively in the shared document (`inline-diagram.png`, `inline-mixed.png`). Captions and credits remain source-backed. Resizing from a larger window to the app's 1,080-point minimum width reflows the table and credit text without losing content (`inline-resized.png`).
- In 60-second timed mode, completing the same 214-character paragraph advances to P012, resets current input, removes the previous figure/table and retains the running timer and accumulated metrics (`inline-timed-advance.png`).
- Macro U06 S04 P017 displays original Figure 6.8a/c balance sheets and explanations successively. At minimum window width, a visible horizontal scrollbar exposes the rightmost Marco + Julia columns and net worth 100. Vertical scrolling retains that horizontal position (`inline-wide-table.png`, `inline-wide-columns.png`). The footer Next control advances correctly outside the clipped source area.
- The longest imported passage, Macro U08 S09 P012, completes at 1,102 correct characters with zero errors. Repeating it and typing 1,101 characters scrolls the last line and caret into view; pause/resume retains progress (`inline-long-caret.png`).
- The restrained Arial typography, dark slate palette, **Reading scope** and **Choose chapters or individual sections** remain. Marketing taglines and both requested footer texts are absent. Source images keep their original lettering.

## Previously verified behavior

Version 1.1 native checks exercised corrected typing, timed advancement, history replay, CSV export through the native save panel, search/scoped selection, empty-scope recovery, settings and attribution. CSV values matched the persisted result (`ui-export-check.json`). These underlying functions remain implemented and covered by core checks; CSV export was not repeated during the inline-media change. The former viewer UI was intentionally removed, so its old screenshots and viewer-specific observations are superseded.

## Limits

Only this Apple Silicon Mac/macOS 26.6.2 was tested. The app declares macOS 14 or later but other releases remain untested. It is ad hoc signed, not Developer ID signed or notarized; do not bypass a macOS warning.

Associations require explicit qualified source references. Eight cross-book references have source evidence. No numbered Table captions were found in the saved HTML; many tables carry Figure numbers, which are preserved. One external ONS Table 2 reference has no saved corresponding table. General phrases such as “the figure above” are not mapped by guesswork. Photographs, covers and decorative imagery are excluded.

Five retained tables contain literal source LaTeX (Macro 7.6; Micro 7.10, 7.11, 7.12, 7.16). Native MathML, sub/superscripts and source formatting are retained; no MathJax or remote scripts are fetched. Prepared paragraph splits and occasional passage LaTeX remain. Micro Figure 3.22's original static summary contains 10 where animation frames contain 12; the static summary is retained verbatim and the discrepancy is audited.

Native visual inspection sampled representative cases, not every figure. Every local asset is hash checked; every retained table is compared with its actual saved source. No source text, captions or values are generated or rewritten.
