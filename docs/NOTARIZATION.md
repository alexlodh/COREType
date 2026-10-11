# Signing and notarizing COREType

This guide is for the person publishing releases. People installing COREType do not need a developer membership or certificate.

Run the steps in order and stop if any command fails. The identity and submission ID in the examples are placeholders to replace.

The current app is ad hoc signed. `scripts/build-app.sh` uses `codesign --sign -`, and `scripts/package-app.sh` rebuilds with that signature. Public GitHub hosting does not notarize it.

Developer ID signing identifies the publisher and seals the app. Apple's notarization service scans the signed release and issues a ticket. Stapling attaches that ticket for offline Gatekeeper checks. This is an automated distribution check, separate from App Store review. See Apple's [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## 1. Set up the developer account and certificate

1. [Enroll in the Apple Developer Program](https://developer.apple.com/programs/enroll/) if you are not already a member. Individual enrollment requires your legal name and an Apple Account with two-factor authentication. Apple lists **99 USD per membership year**, with local pricing shown during enrollment.
2. As the Account Holder, open **Certificates, Identifiers & Profiles → Certificates → + → Developer ID Application**. Create a certificate signing request on the signing Mac, upload it, download the resulting `.cer` and double-click to install it in Keychain Access. That Mac must also retain the corresponding private key. Follow Apple's [certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).
3. Confirm the identity and tools are available:

```sh
security find-identity -v -p codesigning
xcrun --find notarytool
xcrun --find stapler
```

The identity list must include `Developer ID Application: Your Legal Name (TEAMID)`. The existing Command Line Tools installation on the maintainer's Mac includes both tools; install current Xcode or Command Line Tools if yours does not. Keep the private key and notarization credentials out of the repository.

## 2. Build and sign the release

From the repository root, build into the default `dist/COREType.app`. Replace the identity below with the exact Developer ID Application identity printed above:

```sh
bash scripts/build-app.sh &&
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: Your Legal Name (TEAMID)" \
  dist/COREType.app &&
codesign --verify --deep --strict --verbose=2 dist/COREType.app &&
codesign --display --verbose=4 dist/COREType.app
```

The signature details should show your Developer ID authority, TeamIdentifier, `runtime` flag and timestamp. The current bundle has one executable; if future versions add helpers or frameworks, sign those before the outer app. Avoid debug entitlements such as `get-task-allow`. Run the signed build and check typing, saving, CSV export and textbook media before distributing it: hardened runtime changes must be checked on the actual release.

## 3. Store credentials and submit

Create an [app-specific password](https://support.apple.com/en-gb/102654) for your Apple Account. Store the account, Team ID and password using the interactive prompts:

```sh
xcrun notarytool store-credentials "COREType-notary"
```

Do not paste a password into this guide or a shell script. Create a submission ZIP and wait for its result:

```sh
ditto -c -k --sequesterRsrc --keepParent \
  dist/COREType.app dist/COREType-submit.zip &&
xcrun notarytool submit dist/COREType-submit.zip \
  --keychain-profile "COREType-notary" --wait
```

Continue only when the status is **Accepted**. Save the submission ID and retrieve its log, including for successful submissions; replace `SUBMISSION_ID`:

```sh
xcrun notarytool log SUBMISSION_ID \
  --keychain-profile "COREType-notary" dist/notarization-log.json
```

If it is Invalid, resolve the reported signing or runtime problems and submit the corrected build. Apple's [command-line workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) describes submission and logs.

## 4. Staple, check and package that exact app

Staple to the app, then create the distribution ZIP. ZIP archives cannot themselves hold a stapled ticket.

```sh
xcrun stapler staple dist/COREType.app &&
xcrun stapler validate dist/COREType.app &&
codesign --verify --deep --strict --verbose=2 dist/COREType.app &&
spctl --assess --type execute --verbose=4 dist/COREType.app
```

Gatekeeper assessment should succeed with `source=Notarized Developer ID`. Once these checks pass, package the same app and refresh the checksum:

```sh
ditto -c -k --sequesterRsrc --keepParent \
  dist/COREType.app dist/COREType-macOS.zip &&
cp dist/COREType-macOS.zip distribution/COREType-macOS.zip &&
(cd distribution && shasum -a 256 COREType-macOS.zip > SHA256.txt) &&
cp scripts/install-app.sh distribution/install-app.sh
```

**Do not run `scripts/package-app.sh` afterward:** it currently rebuilds and replaces the app with an ad hoc signed copy. The manual commands above preserve the signed, stapled release. When automating this later, signing and notarization belong inside the packaging workflow before its final ZIP and checksum are generated.

Before publication, download and install the final archive on another compatible Mac with download quarantine intact. Confirm normal Gatekeeper opening and app behavior. Then update both READMEs to describe the actual signed release and publish the ZIP, checksum and installer together, optionally as GitHub Release assets. An ordinary first-open download confirmation may still appear.

Repeat signing and notarization for each changed release; rebuilding or changing signed contents requires a fresh signature and submission. See Apple's [stapling instructions](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow#Staple-the-ticket-to-your-distribution).
