# COREType

COREType is an independent, native macOS app for offline typing practice with **The Economy 2.0** by CORE Econ. It includes 6,893 prepared paragraph excerpts across 20 chapters and 271 sections, with relevant original textbook figures and tables alongside the text.

The current app version is **1.5.0**. It removes the remaining-error and completed-paragraph counts from the completion summary. Individual paragraph selection, Previous/Next navigation, timed tests and saved practice history are included.

## Requirements

- The prebuilt ZIP requires an **Apple silicon Mac** (M1 or later) and **macOS 14 or later**. Intel builds have not been verified.
- The app works offline after installation. No account, browser or external runtime is needed to use it.
- Downloading this private GitHub repository requires a GitHub account that has been granted repository access. Receiving a ZIP directly does not require a GitHub account.
- The bundle is **ad hoc signed**, not Developer ID signed or notarized. Downloaded copies may need an app-specific approval; see [Opening a downloaded app](#opening-a-downloaded-app).

Existing native UI observations were made on Apple silicon with macOS 26.6.2. The declared minimum OS is not a claim that every supported OS version has been tested.

## Install from Terminal

### Download from GitHub and install the prebuilt app

Install [GitHub CLI](https://cli.github.com/) and Git first. If you already use Homebrew, `brew install gh` installs GitHub CLI. If macOS prompts to install Command Line Tools when you use Git, finish that installation before cloning.

Authenticate using an account with repository access, then run these commands from a directory where you want to keep the downloaded project:

```sh
gh auth login --hostname github.com --git-protocol https --web
gh repo clone alexlodh/COREType -- --depth 1
cd COREType
bash scripts/install-app.sh
open "$HOME/Applications/COREType.app"
```

The installer checks `distribution/SHA256.txt`, extracts a complete app bundle, checks its executable permission and code signature, and installs it into **your own** `~/Applications`. It uses the macOS tools already available on the device; it does not compile the app or require `sudo`. Its checksum check detects changes to the ZIP relative to the supplied manifest; obtain both files and the installer from a source you trust.

If COREType is already installed, quit it before updating. The installer checks that the existing bundle is COREType, moves that bundle into your Trash and installs the replacement. Settings and history are stored separately from the app.

To use a different writable Applications directory:

```sh
CORETYPE_INSTALL_DIR="/path/to/Applications" bash scripts/install-app.sh
```

Repository access errors, including `Repository not found`, require the owner to grant access to the GitHub account you used. Authentication alone does not grant access to a private repository. See the official [GitHub authentication](https://cli.github.com/manual/gh_auth_login) and [cloning](https://cli.github.com/manual/gh_repo_clone) guides.

### Install a ZIP received directly

Ask the sender for the three files in `distribution/`: `COREType-macOS.zip`, its matching `SHA256.txt` and `install-app.sh`. Put those three files in the same folder, then run:

```sh
cd "$HOME/Downloads"
bash install-app.sh COREType-macOS.zip
open "$HOME/Applications/COREType.app"
```

Use the folder where you saved the files if it is different from Downloads. The sender can share these files without giving access to the repository.

### Build and install from source

Building requires Apple's Command Line Tools (or Xcode), Swift and Python 3. To request Command Line Tools:

```sh
xcode-select --install
```

Wait for that installation to finish. Clone the repository using the GitHub commands above if you have not already done so. From the repository root, quit any running COREType app and run:

```sh
swift --version
python3 --version
CORETYPE_APP_OUTPUT="$HOME/Applications/COREType.app" bash scripts/build-app.sh
open "$HOME/Applications/COREType.app"
```

The build script compiles the release executable, bundles the local excerpts and textbook media, generates the icon, and applies and verifies an ad hoc signature. It assembles the bundle in a temporary directory before replacing the destination. Replaced COREType bundles are moved to Trash. The source checkout can live anywhere; the installed app has no runtime dependency on it. Source builds on Intel Macs are not verified.

## Opening a downloaded app

Try opening the installed app once. If macOS reports an unidentified developer or says Apple cannot check the app, open **System Settings → Privacy & Security**, find the COREType entry under **Security**, and use **Open / Open Anyway** if it is offered. This saves an exception for that app. Apple's [current instructions](https://support.apple.com/en-gb/102445) describe the available approval flow.

For a copy you obtained from a trusted source and chose to approve, the Terminal alternative below removes only COREType's download-quarantine attribute. Check the bundle first; run each command in order and stop if the signature check fails:

```sh
codesign --verify --deep --strict --verbose=2 "$HOME/Applications/COREType.app" &&
xattr -dr com.apple.quarantine "$HOME/Applications/COREType.app" &&
open "$HOME/Applications/COREType.app"
```

Use your chosen install directory if you changed it. Removing this attribute does not notarize the app or repair a damaged bundle. The installer preserves quarantine by default; this step is an explicit choice by the person using the Mac. It does not change the system-wide Gatekeeper setting. A managed Mac may impose additional restrictions.

A plain **“This app can't be opened”** message does not establish the cause. If it persists, check the installed copy:

```sh
sw_vers -productVersion
uname -m
codesign --verify --deep --strict --verbose=2 "$HOME/Applications/COREType.app"
ls -l "$HOME/Applications/COREType.app/Contents/MacOS/COREType"
```

Report that output and how the ZIP was downloaded and extracted. If the installer reports a checksum mismatch, missing executable or invalid signature, download the ZIP and matching checksum again and rerun the installer. A successful ad hoc signature check confirms that the sealed bundle is internally consistent; it does not establish a verified developer identity or Apple notarization.

## Update and uninstall

For a cloned checkout, quit COREType and run these commands from its repository root:

```sh
git pull --ff-only
bash scripts/install-app.sh
open "$HOME/Applications/COREType.app"
```

If you built from source, rerun the source build command after pulling instead. For a directly shared ZIP, obtain the new ZIP and matching checksum from the sender and rerun the installer.

To uninstall, quit COREType and move `~/Applications/COREType.app` to Trash in Finder. Deleting the app leaves your history and preferences available for a later reinstall. To remove those too, separately move `~/Library/Application Support/COREType` to Trash.

## Practice

- Browse Microeconomics, Macroeconomics or both; search chapter and section titles. Expand units and sections to select whole chapters, sections or individual paragraphs, then click **Use this selection**.
- **In order** follows book, unit, section and paragraph order. **Random** chooses a whole paragraph within the selection and avoids an immediate repeat when another paragraph is available. **Previous** and **Next** revisit the navigation path.
- **Passage** ends after the complete excerpt. **Timed** starts on the first typed character and advances through complete paragraphs until the active timer expires. Presets are 15, 30, 60 and 120 seconds; custom duration accepts 1–3,600 seconds.
- Click the passage to focus it. Correct characters brighten, errors turn red and the caret follows your typing. Backspace corrects a character; Option–Backspace deletes to the preceding space. Paste is disabled.
- History separates completed and interrupted tests. Its averages use completed tests only, and CSV export includes detailed metrics. Replay starts the original paragraph.

| Shortcut | Action |
| --- | --- |
| Command–R | Repeat the starting paragraph |
| Command–N / Return after completion | Next paragraph |
| Escape / Command–P | Pause or resume |
| Command–T | Focus the passage |
| Command–1 / Command–2 | Practice / History |

Leaving the app, opening modal settings or navigating to History pauses an active test. Arrow keys do not move the input position. Straight/curly quotes and hyphen/en/em dash equivalents match by default; strict matching is available in Settings.

### Textbook figures and tables

Relevant original figures and tables appear after the passage in the same scrolling area. Captions and credits accompany them. **Settings → Show textbook figures and tables** controls their visibility and saves the preference for the current user. They are reading context and do not count toward the typing target. Wide tables scroll horizontally.

The bundled catalogue covers 585 source figures, with 525 original images and 95 table assets. It supports 1,140 passages. Some source tables retain literal LaTeX; an external ONS Table 2 reference has no saved table. Source associations, exclusions and discrepancies are documented in the verification files.

### Metrics

Five characters, including spaces and punctuation, count as one standard word. Paused time is excluded.

| Metric | Definition |
| --- | --- |
| WPM | Retained correct characters ÷ 5 ÷ active minutes |
| Raw WPM | All character attempts ÷ 5 ÷ active minutes, including retyped characters |
| Accuracy | Correct character attempts ÷ all character attempts × 100 |
| Error rate | Incorrect character attempts ÷ all character attempts × 100 |
| Mistakes | Incorrect attempts, including those later corrected |
| Corrections | Incorrect characters removed with Backspace |

Backspace is not a character attempt. Completed timed paragraphs cannot be backspaced into; their statistics remain accumulated. A passage ends when its final character is typed, even if that character is incorrect. Extremely short tests can produce unstable speed estimates.

## Local data and privacy

Each macOS user has their own preferences and up to 1,000 recent results in:

```text
~/Library/Application Support/COREType/state.json
```

Data is saved atomically. An unreadable state file is backed up before recovery, and write failures are shown in the app. In-progress text is not restored after quitting; attempted sessions are recorded as interrupted. The app works offline, does not transmit practice data, and does not read or modify Monkeytype's browser storage. Excerpts, images and tables are bundled with the app.

## Development and packaging

| Path | Contents |
| --- | --- |
| `Sources/TypingCore` | Swift typing engine, passage selection and persistence |
| `Sources/COREType` | SwiftUI interface, AppKit typing surface and offline WebKit media renderer |
| `Tests/TypingCoreTests` | Dependency-free core checks |
| `scripts` | Import, build, installation and packaging tools |
| `distribution` | Current prebuilt app ZIP and SHA-256 manifest |
| `verification` | Historical test results, performance measurements and source audits |
| `import-source` | Preserved inputs for reproducible import |

Run the core checks from the repository root:

```sh
bash scripts/test.sh
```

Build the app ZIP and refresh its checksum:

```sh
bash scripts/package-app.sh
```

Packaging builds into a temporary directory, archives the complete app with macOS `ditto`, extracts it again and verifies its signature, executable and bundle metadata before updating `distribution/COREType-macOS.zip`, `distribution/SHA256.txt` and a copy of `install-app.sh`. It packages the current source version; the included installer supports Apple silicon. Upload/share those three files together. Future Developer ID distribution requires a signing certificate and Apple's notarization workflow; an ad hoc signature does not provide that approval.

Compiler and SwiftPM caches stay inside `.build`. `scripts/swift-env.sh` uses the native SwiftPM backend for compatibility with the recorded Command Line Tools setup. Its build-process sandbox flag affects SwiftPM compilation, not macOS app security. `ViewState` aliases `SwiftUI.State` to support toolchains where the newer `@State` macro plugin is supplied only with Xcode.

For isolated UI work, launch with `--ui-testing`; state goes to `/tmp/COREType-UI-Testing/state.json`. `--fixture "CORE Micro U01 S06 P008"` selects that passage only in the testing profile. Optional `--performance-report /tmp/coretype-counters.json` writes developer counters; normal launches produce no diagnostic files.

Recorded historical checks and their limits are in [CPU optimization](verification/CPU-Optimization.md), [UI verification](verification/UI-Verification.md) and [code cleanup](verification/Code-Cleanup.md). These are observations from the recorded test environment, not verification of a recipient's Mac. The typing document and cosmetic timer were optimized in 1.4; measurements and unresolved coverage are described in the performance report.

Current packaging and installer checks are recorded in [Terminal installation verification](verification/Installation.md).

## Source integrity and attribution

The library contains prepared excerpts rather than the complete textbooks: 3,505 Microeconomics paragraphs and 3,388 Macroeconomics paragraphs. The preparation omitted front matter, glossaries, references and equation-heavy material; some long paragraphs were split before import. Some plain-text LaTeX and exercise material remain. Imported paragraph text, order and verified section metadata are preserved.

To regenerate the library from the preserved inputs:

```sh
python3 scripts/import_library.py import-source
```

Figure and table import supports fetching missing original assets or using the verified local cache:

```sh
python3 scripts/import_diagrams.py import-source
python3 scripts/import_diagrams.py import-source --offline
python3 scripts/import_diagrams.py import-source --verify-tables
```

`--offline` requires the cached assets and verifies their source URLs and SHA-256 hashes. `Source-Audit.json`, `verification/diagram-audit.json` and `verification/preserved-import-hashes.json` record source mapping and integrity evidence. The optional independent `verification/table-source-compare.py` requires BeautifulSoup 4; the app and core checks require no external Python packages.

The original Monkeytype setup archive, prepared pool, provenance, source HTML and original import README are retained under `import-source/`. Textbook attribution and **CC BY-NC-ND 4.0** terms are included in `Attribution.txt`, the original import README and the app's Credits & help dialog. Use the excerpts for noncommercial practice and retain the supplied attribution when sharing the app. No CORE Econ or Monkeytype endorsement is implied.
