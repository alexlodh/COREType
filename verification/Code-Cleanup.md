# COREType 1.3 code cleanup — 11 October 2026

This pass replaces the separate figure viewer with automatic textbook context in the typing document. It also removes the state, controls and generated resources made obsolete by that change. The work is scoped to that implementation and its build/import paths; it does not claim that every future maintenance concern has been eliminated.

## Changes

- Deleted `FigureView.swift`, the figure sheet, passage-header viewer button, item picker, zoom controls and previous/next controls. Removed `showingFigures`, `showFigures()` and the corresponding command/input guards.
- Added one AppKit typing document containing the passage and inline source material in a shared vertical scroll. Text input and the caret remain in the native text view. Wide source tables retain horizontal scrolling.
- Added the saved `showTextbookMedia` preference, enabled by default. Older saved preferences decode with that default; saved opt-out, scope, duration, order, font size, punctuation preferences and history are preserved. Changing media visibility does not reset the typing engine.
- Moved common typography, colors and the CLI-compatible `ViewState` alias into `Appearance.swift`. Inline source captions and credits use the same restrained Arial presentation.
- Replaced repeated linear figure lookups with an identifier index. Source-proven passage associations still enforce book isolation and the explicit cross-book exceptions.
- Removed the duplicate app-termination notification path. `AppDelegate` owns final session archiving and saving.
- Changed the app build from copying over an old bundle to assembling a fresh complete bundle under `/tmp`. Signing and strict verification precede replacement. The previous output is moved to Trash after an ownership check against `org.sasha.coretype`; unrelated apps, symlinks, files and malformed bundles are rejected.
- Added a shared Foundation Trash helper for recoverable generated-file replacement. The importer checks prior asset hashes before moving obsolete table HTML to Trash.

## Source table selection

The old viewer imported repeated source slideshow steps for seven Microeconomics figures. Inline display now uses their source-authored static summary tables: Figures 2.5, 2.9, 2.10, 3.4, 3.10, 3.21 and 3.22. The source HTML explicitly identifies each as a `figure summary` container.

Macro Figure 6.14a's summary table has blank columns. Its final source frame, `figure-6-14ae`, completes those columns while preserving every preceding nonempty cell. That original complete table is selected. Distinct before/after balance sheets and exercise/answer tables remain, including Figures 6.3a/c/e, 6.8a/c and 6.20b/d/f.

Thirty-three superseded generated table files were moved to Trash, leaving 95 referenced table assets across 87 figures. Every retained cell, header, span and caption is source-backed. The saved source pages and original Monkeytype setup remain untouched. Source-selection evidence and exact Trash moves are recorded in `diagram-audit.json` and `cleanup.json`.

Micro Figure 3.22 has a source inconsistency: its static summary lists household paid work as 10, while the animation lists 12. The source-authored static summary remains unchanged; this app does not correct or combine the source values.

## Preserved behavior and verification

The complete prepared library remains byte-identical: 6,893 paragraphs, 20 chapters and 271 sections. All 525 original images, 1,140 passage mappings, 1,315 figure associations, source captions and credits are preserved. The library SHA256 remains `cd0bb0d8cd3b4ec4443df7f4144f72c19f20130569599d8d4c2431253ccbedcb`.

Typing metrics, correction, Unicode handling, punctuation equivalence, timer completion, timed paragraph continuation, pause/resume, scope selection, random/order modes, shortcuts, local history, replay and CSV export remain implemented. Source material is excluded from typing targets and metrics. Attribution and CC BY-NC-ND 4.0 terms remain available in the app and preserved import README.

- 18 core checks, 34,263 assertions, zero failures.
- 18 source-table checks, zero failures.
- Independent HTML comparison: 95 assets, 618 rows, 2,663 ordered cells, 96 spanning cells, 361 inline formatting elements and 12 inert source links; zero mismatches.
- Two offline imports produced the same catalogue SHA256: `0e7cd966cdd835de9c856fca6c3c20e2ba4357b67fc346f57cbe6f5c9c90b3e8`.
- Build-output ownership checks accepted COREType and rejected a foreign app, file, malformed bundle and symlink without changing those inputs.

Native behavior and release signature observations are documented separately in `UI-Verification.md` and `release-validation.json`.

## Remaining constraints

The CLI toolchain still needs SwiftPM's native backend and the `ViewState` alias; these are documented compatibility requirements. The app is ad hoc signed and has only been tested on this Apple Silicon Mac. Build caches and normal user state are excluded from source/release archives.

Five retained source tables contain literal LaTeX: Macro 7.6 and Micro 7.10, 7.11, 7.12 and 7.16. One external ONS Table 2 reference is absent from the saved source and remains unavailable. Source photographs and unqualified references are not assigned invented associations. The source library retains its previously prepared splits and remaining notation.
