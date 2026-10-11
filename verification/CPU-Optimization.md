# COREType 1.4 CPU optimization — 11 October 2026

The completed measurements below cover active native input, focused ready state and an isolated AppKit renderer workload. Coverage limits are explicit; no unmeasured scenario is presented as a measured gain.

## Comparison and method

Baseline: audited commit `b082fd0a67afc8b05e38780015c4c31017f95098`, tag `v1.3.0`, app version 1.3 / build 4. Optimized source release identifier: `v1.4.0`, app version 1.4 / build 5. Both builds use Swift release optimization on the same Apple Silicon Mac/macOS 26.6.2. The baseline bundle was retained outside the synced workspace for comparison. Optimized bundle paths, executable/package hashes and exact resource matching are recorded in `cpu-release-integrity.json`; fixture, font, window and media conditions are stated below.

Native input and focus/scroll actions use CUA with `--ui-testing`, isolated at `/tmp/COREType-UI-Testing/state.json`. The normal profile is preserved. `--fixture "<passage ID>"` is accepted only in the UI-testing profile and establishes a reproducible optimized-build start passage. Launch and first media load are separate from warmed steady-state windows.

Process CPU uses `scripts/measure-process.py`: monotonic wall duration and macOS `proc_pid_rusage` cumulative user + system CPU. **100% means one logical core.** Report elapsed seconds and CPU seconds for every run, plus median/range CPU percent. Completed scenarios use three 30-second windows per reported build, with warm-up stated below. No samples run during the CPU comparison. Only the explicitly selected COREType main process is included; unattributed WebKit processes from other apps are excluded.

Command Line Tools provide Swift 6.4 and `/usr/bin/sample`. Full Xcode/Instruments/xctrace are unavailable; no installation or security setting changes are made. Signposts, Instruments allocation counts and independently attributed WebKit/GPU helper CPU are therefore not claimed. Counters are opt-in and disabled on normal launches. Counter runs and synthetic engine/renderer benchmarks are separate from native CPU comparisons. Maximum-speed benchmark typing is a stress workload, not representative WPM or human latency.

## Native process measurements

The core phase comparisons use a 1,260×850 window, 24-point passage font, textbook media enabled and the no-reference passage Macro U06 S04 P001. Each active-input run types the same 144 characters through CUA at a target five characters/second. Three 30-second windows are recorded per completed scenario/build. Ready and non-input phases use five-second helper warm-up; active captures begin after operator setup with no additional helper warm-up. Only the main COREType process is included.

| Scenario / build | Elapsed seconds (runs 1/2/3) | Cumulative CPU seconds (runs 1/2/3) | Median CPU % (range) | Evidence |
| --- | --- | --- | --- | --- |
| Ready, focused — baseline | 30.004914 / 30.004187 / 30.004825 | 0.004851548 / 0.004726957 / 0.005425796 | 0.016169178 (0.015754325–0.018083078) | `cpu-native-baseline-ready.json` |
| Ready, focused — optimized recheck | 30.001753 / 30.002499 / 30.005177 | 0.003923780 / 0.004001421 / 0.003628589 | 0.013078502 (0.012093210–0.013336959) | `cpu-native-optimized-ready-recheck.json` |
| Running without input — optimized | 30.002365 / 30.001225 / 30.004433 | 0.061080052 / 0.063140143 / 0.062425576 | 0.208054510 (0.203584125–0.210458549) | `cpu-native-optimized-running.json` |
| Active native input — baseline | 30.001342 / 30.005060 / 30.000519 | 0.284523608 / 0.349604540 / 0.413940227 | 1.165151941 (0.948369588–1.379776885) | `cpu-native-baseline-active-1.json`, `cpu-native-baseline-active-2.json`, `cpu-native-baseline-active-3.json` |
| Active native input — optimized | 30.005104 / 30.000545 / 30.004761 | 0.129624085 / 0.145840118 / 0.136163113 | 0.453805021 (0.432006778–0.486124889) | `cpu-native-optimized-active-1.json`, `cpu-native-optimized-active-2.json`, `cpu-native-optimized-active-3.json` |
| Paused — optimized | 30.002660 / 30.000713 / 30.003059 | 0.000046461 / 0.000157100 / 0.000010507 | 0.000154856 (0.000035020–0.000523654) | `cpu-native-optimized-paused.json` |
| Finished — optimized | 30.000588 / 30.001239 / 30.004871 | 0.000467642 / 0.000014324 / 0.000010336 | 0.000047745 (0.000034448–0.001558776) | `cpu-native-optimized-finished.json` |
| History — optimized | 30.004268 / 30.005073 / 30.005125 | 0.000015167 / 0.000012022 / 0.000011152 | 0.000040067 (0.000037167–0.000050549) | `cpu-native-optimized-history.json` |

Active native input median CPU changes from **1.165152% to 0.453805%**, a **61.05% reduction** in this controlled workload. Median CPU time per 30-second window changes from 0.349605 to 0.136163 seconds (approximately 0.213 seconds less main-process CPU). Baseline active costs are already modest; this is a workload-specific reduction, not a promise of previously sustained high CPU or a hardware-independent speedup.

The optimized focused-ready recheck followed explicit native activation and focus. Both ready medians are below 0.02% of one core (about 4–5 milliseconds CPU per 30 seconds); the small absolute difference is reported without a headline percentage gain. The initial optimized-ready capture is **withdrawn as focused-ready evidence** because native focus/visibility was not confirmed; `cpu-native-optimized-ready-initial-withdrawn.json` retains it. The initial baseline-running set may overlap a compiler workload, so `cpu-native-baseline-running.json` remains a preliminary record and no running-without-input reduction is claimed. `cpu-native-withdrawn-captures.json` identifies the exact excluded report hashes. Paused, finished and history have no matched baseline captures in this release verification.

Optimized paused, finished and history phase captures consume about 10–468 microseconds of main-process CPU per 30-second window, with 10–14 interrupt-wakeup increments and approximately zero package-idle wakeups. These observations support very little inactive work on this Mac. At this scale, percent speedups would obscure the absolute cost and OS measurement variation; exact zero CPU is not claimed. Framework/OS wakeup counters are not direct Timer-firing counts.

Native resident/physical footprint values are retained per window in the JSON. Active baseline resident memory spans 160.52–177.09 MiB, versus 138.62–162.42 MiB optimized; physical footprint spans 205.22–214.61 and 182.24–210.20 MiB respectively. Capture/run startup variation remains, including first-window changes. These are main-process observations and do not establish a controlled source-renderer retention tradeoff or independently attributed WebKit-helper memory. Native end-to-end input latency remains unquantified; observed responsiveness and source scrolling are recorded functionally below.

Background observations have different lifecycle states and are **unpaired diagnostics**, so no relative gain is calculated:

| Diagnostic state / build | Elapsed seconds (runs 1/2/3) | CPU seconds (runs 1/2/3) | Median CPU % (range) | Evidence |
| --- | --- | --- | --- | --- |
| Hidden running baseline | 30.005051 / 30.005068 / 30.002897 | 0.180428116 / 0.182398737 / 0.192456337 | 0.607893101 (0.601325802–0.641459186) | `cpu-native-baseline-background-minimized.json` |
| Minimized inactive optimized | 30.005053 / 30.005068 / 30.004347 | 0.000008507 / 0.000008085 / 0.000010326 | 0.000028352 (0.000026945–0.000034415) | `cpu-native-optimized-background-minimized.json` |

The baseline diagnostic has package-idle wakeups 9/16/21 and interrupt wakeups 513/514/506; optimized has 0/2/1 and 10/10/10. These are OS process counter increments, not attributed timer counts. The different running/inactive and window states prevent a controlled comparison.

At the user's request to finish and push the release, the additional native CPU matrix was stopped. Three-run native CPU comparisons for media-disabled, SVG, wide-table, longest-passage and active resize/scroll fixtures were not collected. Their functional observations below and the isolated renderer benchmark remain distinct from the core native CPU windows. Native typing-stack attribution and end-to-end latency are unmeasured; cold-launch/first-media-load limits are stated next.

## Launch and first-media-load limits

CUA app selection encountered an approximately five-second `getApp` wait/timeout while resolving the test app. That measures an automation wait limit, including app/session discovery and initial state retrieval; it is not a launch-to-first-frame or first-source-load timing. The app subsequently rendered the verified fixtures, but this run has no monotonic timestamp pair from launch to visible content or from HTML navigation to first complete source rendering. Cold-launch and first-media-load durations therefore remain unquantified. Steady-state CPU windows and renderer update latencies exclude setup/warm-up and cannot establish cold-load latency. No launch or first-media regression is inferred from the CUA timeout.

## Isolated renderer measurements and update counts

The release-optimized harness exercises the production AppKit renderer without a native window. The renderer capture predates the final native-window occlusion guard; its unattached rendering path is unchanged by that final guard. Both variants use Macro U08 S09 P012 (1,102 graphemes), a 960×480 viewport, 23-point font, media disabled, five input events/second and ten metric refreshes/second. Inputs include ordinary source characters, periodic wrong emoji and Backspace. Each variant has three 30-second steady windows after two seconds of warm-up per run. `cpu-renderer-baseline.json` and `cpu-renderer-optimized.json` retain exact source hashes and per-run measurements.

| Renderer measurement | Baseline | Optimized |
| --- | --- | --- |
| Elapsed seconds, runs 1/2/3 | 30.0053 / 30.0056 / 30.0071 | 30.0026 / 30.0047 / 30.0048 |
| CPU seconds, runs 1/2/3 | 0.492150 / 0.418142 / 0.576061 | 0.165636 / 0.128774 / 0.184199 |
| Median CPU % (range) | 1.640213 (1.393548–1.919749) | 0.552073 (0.429180–0.613898) |
| Median update duration, runs 1/2/3, ms | 2.021 / 1.582 / 4.037 | 0.601 / 0.548 / 0.793 |
| p95 update duration, runs 1/2/3, ms | 6.102 / 5.723 / 5.990 | 2.036 / 1.887 / 2.304 |
| Maximum update duration, runs 1/2/3, ms | 13.257 / 6.202 / 7.492 | 5.107 / 2.412 / 2.850 |
| Peak resident memory, including setup | 106.36 MiB | 84.20 MiB |

Median renderer-harness CPU falls by **66.3%**, with lower observed update durations. This is evidence for the isolated renderer workload. It excludes native drawing, caret blinking, SwiftUI body evaluation, native end-to-end input latency and attributable WebKit-helper CPU. The media-disabled benchmark does not measure source-load latency or claim a native-app memory gain. Maximum-speed engine stress results are not used as a native performance claim.

The counters cover setup, warm-up and all three active windows (450 input events), whereas CPU and latency exclude setup/warm-up:

| Instrumented operation | Baseline | Optimized | Interpretation |
| --- | --- | --- | --- |
| Representable update calls | 903 | 453 | Optimized harness omits clock-only representable updates, matching the narrowed production observation path. |
| Full attributed-text rebuilds | 453 | 3 | Three initial passages; subsequent optimized input uses 450 edited character ranges. |
| Changed incremental character ranges | — | 450 | NSTextStorage batching preserves the expected source/error attributes. |
| Document fit passes | 906 | 33 | Geometry guards suppress unchanged fits. |
| Explicit `ensureLayout` requests, counter `text.fullLayouts` | 906 | 33 | These are request counts; they do not prove AppKit fully relaid out the document each time. |
| Full-view invalidation requests | 903 | 0 | Invalidation scope is measured; actual drawn pixel work is not inferred. |
| Caret-region invalidation requests | — | 486 | No attached window/blinking is exercised by this harness. |
| Web view creations | 3 | 0 | Baseline eagerly creates one per fresh media-disabled harness; optimized creation is lazy. |
| HTML loads | 3 | 0 | Baseline loads empty setup documents. Neither implementation reloads HTML on every timer tick. |

Evidence: `cpu-renderer-baseline-counters.json`, `cpu-renderer-optimized-counters.json`. Native clock-only body/scope/source counters and inactive blink/timer transition counts were not captured. Timer suppression is checked by deterministic policy tests and implementation review; native process observations do not establish exact firing counts. Counters describe actual SwiftUI body evaluations, explicit layout calls or invalidation requests according to their names, not assumed complete redraws.

Counters are enabled only by `--performance-report <path>` and flushed on save, pause, navigation and quit transitions. No timer tick performs report I/O. The native document has explicit passage, input, font and media revisions; there is no complete target/input string signature.

## Implemented changes

- AppModel remains the action coordinator. PracticeDisplay observes input/phase/focus, and MetricsDisplay observes one metrics snapshot per visible refresh. Clock changes do not publish through the coordinator, practice document, scope browser or history.
- Selected counts sum cached section counts. Search runs only on query/book-filter changes. Full chapter section sets and current source figures are cached. Completed history counts, average/best speeds and graph values refresh only when results change.
- The cosmetic metric timer exists only for a running, visible, focused practice view in the active app's visible key window. It retains the 0.1-second cadence with 0.02-second cosmetic tolerance. A separate zero-tolerance timed deadline runs in common run-loop modes, is cancelled on pause/reset/finish and uses the true monotonic deadline after resume. Input and Backspace independently enforce expiry. Main-loop callbacks use compiler-checked MainActor isolation without one Task allocation per tick; timers and observers are cleaned up.
- The attributed passage is built once per passage/font change. NSTextStorage batching updates the edited character ranges, with a full rebuild fallback at passage/style changes. Extended grapheme counts and UTF-16 range mapping preserve wrong glyph lengths, source-equivalent punctuation, wrong-space rendering, Unicode corrections and wrapping.
- Document/container/frame assignments and explicit layout requests are conditional on geometry changes. Caret geometry is cached; blink invalidates the caret rectangle and stops for paused, finished, hidden, unfocused, background or offscreen carets.
- Retained correct/error counters are maintained in TypingEngine, including deletion, word deletion and timed advancement. Metrics no longer allocate filtered input collections. A fixed punctuation-group mapping replaces mismatch-time Set construction.
- WKWebView is created only for enabled source material. Empty passages/opt-out never load empty HTML. One created renderer is retained for reuse, preserving quick toggles; media navigation/measurements reject stale generations and coalesce width queries. Original resources, navigation restrictions and source fidelity remain unchanged.

## Correctness and source integrity

The implementation run of `bash scripts/test.sh` passed **25 checks, 253,258 assertions, zero failures**. Seven added checks cover randomized incremental metrics versus a scanning reference, exact punctuation equivalence, repeated-target render revisions, exact deadlines with repeated pauses and late input/deletion, Unicode UTF-16 range edits, cosmetic-timer lifecycle policy and deadline independence from suppressed display updates. `bash scripts/swift-env.sh build --product COREType -c release` passed. Saved evidence: `cpu-core-tests.log` and `cpu-build.log`; the staged release bundle build completed successfully. Installed/package signature verification is recorded below.

Current resource hashes were directly checked with `shasum -a 256` and equal the audited baseline:

| Resource | SHA256 |
| --- | --- |
| `Sources/COREType/Resources/library.json` | `cd0bb0d8cd3b4ec4443df7f4144f72c19f20130569599d8d4c2431253ccbedcb` |
| `Sources/COREType/Resources/Diagram-Catalog.json` | `0e7cd966cdd835de9c856fca6c3c20e2ba4357b67fc346f57cbe6f5c9c90b3e8` |

Preserved source: 6,893 passages, 20 chapters, 271 sections, 525 original images, 95 table assets, 1,140 mapped passages and 1,315 source associations. Captions/credits, explicit cross-book references, CC BY-NC-ND 4.0 terms, offline loading and saved media toggle are preserved. The `ViewState<Value> = SwiftUI.State<Value>` CLI compatibility alias remains.

`python3 scripts/import_diagrams.py import-source --verify-tables` was rerun successfully: **18 source-table checks, zero failures, all 95 assets verified**. The library and catalogue hashes above remain unchanged. `cpu-source-regression-check.json` confirms preservation of prior figures/associations and all 525 original image bytes. The independent historical source comparison remains in `table-source-comparison.json` (95 assets / 2,663 ordered cells / zero mismatches). `cpu-import-integrity.json` verifies all **338 listed preserved import files**, totalling 28,222,242 bytes, against the original committed SHA256 manifest: all match, zero failures. Its scope is the repository's preserved `import-source` copies; external original workspace paths were not inferred or modified.

The actual optimized NSTextStorage renderer also passes **58,428 display/attribute/caret assertions across 1,600 randomized operations**, with zero failures (`cpu-renderer-check.json`). It covers emoji/ZWJ/combining and non-BMP wrong glyphs, precomposed/decomposed encoding changes, wrong spaces, equivalent punctuation, word deletion, font changes, repeated snapshots and timed target changes against a full rebuild reference. CUA cannot inject the relevant native emoji text on this toolchain, so these are real AppKit differential checks; native keyboard emoji/IME behavior is not claimed verified.

The isolated UI-test bundle helper preserves the original optimized executable/resources and uses a distinctly identified signed wrapper to supply testing flags. Five lightweight rejection checks confirm canonical `/tmp` containment, source-descendant rejection, refusal to reuse the release bundle identifier and rejection of malformed identity strings (`cpu-test-bundle-checks.json`); no app was created by those rejection checks.

## Native regression observations

The fixture observations below were made through CUA using the isolated UI-testing profile. They are recorded as operator observations; the report does not imply that a screenshot was retained for each action. The installed-app history check uses the normal profile and is separately recorded in `cpu-profile-preservation.json`.

| Fixture / action | Current 1.4 observation |
| --- | --- |
| Micro U01 S06 P008 | Figure 1.8a's original table appears after the 235-character passage. Toggling source during partial input preserves input and statistics. Clicking the source then typing returns to the caret. Paused shared scrolling reaches the final 3,000 / 946,000 grain row, caption and licence. |
| Micro U02 S04 P011 | Original Figure 2.4 SVG and matching source table render inline. A custom two-second timed test accepts 214 source characters, advances to P012, removes preceding media and retains 214 accumulated correct characters. Late input is rejected after expiry. |
| CSV / history replay from the two-second result | CSV records 214 attempts, 1,284 WPM and 2.00 seconds, matching the saved result. History replay resets to the original P011 passage with fresh input/statistics. |
| Macro U06 S04 P017 | Horizontal dragging exposes Marco + Julia columns. Vertical scrolling retains horizontal position. Resize from 1,260×850 to 1,098×772 preserves readable media without clipped footer controls; Next advances to P018. |
| Macro U08 S09 P012 | At 1,101 of 1,102 characters, the final caret is visible. Pause/resume preserves progress, and typing the final period completes with 1,102 retained correct characters. |
| Unicode, punctuation, wrong spaces and Option–Backspace | Covered by engine and actual NSTextStorage differential checks. Native emoji/IME injection is unsupported by the CUA toolchain and remains unverified. |
| Rapid passage/font changes, source toggle/relaunch, empty scope, filtered whole-chapter selection and visibility transitions | Source toggle, live resize, history replay and passage changes were observed above. Rapid repeated font/passage changes, source-toggle relaunch, empty-scope UI, filtered whole-chapter UI selection and the complete focus/visibility transition matrix were not repeated natively for 1.4; relevant core/policy checks passed. |

`UI-Verification.md` retains the separate 1.3 observations. Every native case in that historical report is not automatically represented as repeated in 1.4. `cpu-profile-preservation.json` records byte-exact normal-profile preservation across installation and the new app's CUA launch, with five saved results before/after and five visible history results. The preceding normal session was completed and already saved; no unfinished session was discarded, and no native typing was performed in the normal profile.

## Deferred options and practical limits

The retained changes reduce observed renderer CPU/update duration and explicit rebuild/layout/invalidation counts with limited architecture changes. The cosmetic display remains at 10 Hz. A lower refresh rate was not adopted because isolating observation removes the document/side-browser clock work while preserving tenths-of-a-second feedback. Caret blinking retains a 0.4-second conditional timer; there is no display link or continuous animation loop.

One lazy-created WebKit renderer remains retained after first media use so toggles reuse a loaded source document. It trades retained memory for switch latency; this run does not measure eviction versus recreation or WebKit-helper memory independently. Aggressive media eviction/virtualization and extra table/asset caches are deferred because the existing revision/width guards eliminate recurring document reloads, shared scroll stability has been observed, and original SVG/table/MathML source integrity remains verified. A native image/table replacement would add fidelity complexity without measured evidence that WebKit dominates the optimized active workload.

Persistence remains an atomic synchronous save on settings/archive/completion. Routine keystrokes do not save history. Font-slider coalescing or a serialized background writer is deferred because no new measured persistence stall establishes its need, and completion durability/order must remain exact. The moderate library keeps cached scope/search/history derivations; database migration or asynchronous startup decoding lacks a measured cold-start benefit here.

No source text/image/table is rasterized, rewritten, deleted or hidden as the performance fix. Original imports, attribution and offline safeguards remain. Framework/compiler migrations, `-Ounchecked`, broad asynchronous drawing, App Nap overrides, GPU forcing and security changes are outside the measured improvements. Allocation counts, native end-to-end latency, cold-load timing and per-WebKit-helper CPU remain limited by available tooling and measurement coverage; the report makes no hardware-independent CPU promise.

## Release validation

The source release identifier is **v1.4.0**, version **1.4**, build **5**. `cpu-release-integrity.json` confirms strict signature verification for the staging app at `/private/tmp/COREType-Release/COREType.app`, installed app at `/Users/alexlodh/Applications/COREType.app`, and ZIP-extracted copy. All 630 app-file bytes match across the three copies, including the unchanged library/catalogue hashes.

- Executable SHA256: `ae8db8ec144a9429f1fce909432475dc176e1f503b2510b659fe89ccfe987ad5`.
- Application ZIP SHA256: `f36d2d4ed2b567fb19bc2dcfd980f485b8bf1ecc7cb9c3dfe5097d432903eb02`.
- Normal profile and installed-app launch/history verification: `cpu-profile-preservation.json`.

Release packaging excludes compiler caches and personal state. Superseded generated bundles/packages are moved to recoverable Trash, with the release helper's exact cleanup record referenced in `cpu-release-integrity.json`. Existing historical verification files remain identifiable as historical evidence. The Git release tag identifies the final source commit without embedding a self-referential commit hash in this report; the final remote push record is supplied with the release outputs.
