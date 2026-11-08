# Direct-distribution beta

The regular `build.sh` produces a locally ad-hoc-signed development app. It is not a notarized beta for other users.

## One-time Apple setup

1. Use an Apple Developer Program account and install a **Developer ID Application** certificate with its private key in the macOS Keychain. This certificate is for distribution outside the Mac App Store.
2. Store notarization credentials using `xcrun notarytool store-credentials` and give the Keychain profile a name, for example `toneboy-notary`. Enter credentials locally; do not commit passwords or private keys.
3. Check that `security find-identity -v -p codesigning` lists the certificate.

## Build and notarize

```sh
export TONEBOY_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export TONEBOY_NOTARY_PROFILE='toneboy-notary'
bash package-beta.sh
```

The script checks the identity and credentials, builds a separate hardened-runtime app in `../beta`, signs and uploads it to Apple's notarization service, requires an Accepted response, staples the ticket, and runs Gatekeeper assessment. Only then does it write `../beta/toneboy-beta.zip`. It does not replace the regular development app or create a GitHub release.

The package contains no extra audio driver or helper installer. Ask testers to extract the app and put it in Applications before launching, grant System Audio Recording, and optionally enable **Launch at Login** from the menu. If macOS requires login-item approval, the app offers a Settings link. Registration is opt-in, not performed during startup.

## Before wider distribution

- Verify launch at login on a signed build; registering is not proof that a real logout/login works.
- Test audio permission denial/regrant, Bluetooth/AirPods, output changes, long playback, and sleep/wake on hardware.
- Confirm no feedback, doubled audio, or stuck mute during interruption and exit.
- This flow retains the existing bundle identifier and non-sandbox packaging. App Store sandbox migration, App Store signing, and store assets are separate work.

## Current validation

The initial missing-identity preflight and script syntax were checked. A Developer ID Application identity was subsequently installed, and the beta was signed with hardened runtime and a secure timestamp. Apple notarization returned Accepted; ticket stapling and validation succeeded; Gatekeeper accepted the app as Notarized Developer ID. The final ZIP was produced after stapling. These steps were executed individually using the same commands as the release script. Hardware testing and a real logout/login remain outstanding.
