# Terminal installation verification

Recorded 11 October 2026 for COREType 1.5.0, build 9, on Apple silicon.

`scripts/package-app.sh` rebuilt the app into a temporary directory, created its ZIP with `ditto`, extracted it again and verified the extracted bundle with `codesign --verify --deep --strict`. Its executable and Info.plist matched the pre-archive copies. The resulting executable architecture was `arm64`.

The packaged ZIP SHA-256 was:

```text
d33c5d5a97a258079942c3ee4a67c0710d85a316cd18bd4ffb0299277a1a7ca9
```

Seven installer checks passed using temporary destinations and generated fixtures:

| Check | Observation |
| --- | --- |
| Fresh installation | A directory containing spaces received version 1.5.0 with an executable binary and valid signature. |
| Update | The prior verified bundle moved into Trash and the replacement verified successfully. The generated prior bundle was recovered for test cleanup. |
| Checksum mismatch | Installation stopped before creating the target app. |
| Unrelated existing application | A bundle with a different identifier was refused and retained. |
| Symlink destination | The installer refused to replace it and retained the link. |
| Standalone shared files | The installer worked alongside the ZIP and checksum outside the source checkout. A synthetic download-quarantine attribute remained on the installed app. macOS normalized the attribute metadata during copying. |
| Optional quarantine approval | The documented removal command affected only the generated test app. The attribute was absent afterward. |

Shell syntax checks passed for the build, packaging, source installer and distributed installer. The two installer copies matched byte for byte.

The app is ad hoc signed and has no Developer ID notarization. This report verifies packaging and installation on the recorded environment. Launch on a recipient's Mac and the cause of a recipient's generic launch error remain unverified.
