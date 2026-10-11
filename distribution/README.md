# COREType 1.5.0 for macOS

`COREType-macOS.zip` contains the ad hoc signed Apple silicon app for macOS 14 or later. `SHA256.txt` identifies the exact archive. Version 1.5.0 removes the remaining-error and completed-paragraph counts from the completion summary.

From the repository root, install for the current macOS user with:

```sh
bash scripts/install-app.sh
open "$HOME/Applications/COREType.app"
```

The installer checks the archive checksum and app signature and preserves a replaced COREType bundle in Trash. It requires no compiler or `sudo`. When sharing directly, include the three files in this directory: `COREType-macOS.zip`, `SHA256.txt` and `install-app.sh`; recipients can run the installer with the ZIP path.

The repository is public; no GitHub account is needed to download these files. See the [project README](../README.md) for direct Terminal downloads, building from source, app-specific quarantine approval, troubleshooting, updates and attribution. The bundle is not Developer ID signed or notarized; the [maintainer guide](../docs/NOTARIZATION.md) explains the release process. Historical native observations used Apple silicon with macOS 26.6.2; other OS versions have not been independently verified.
