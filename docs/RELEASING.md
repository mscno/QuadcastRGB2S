# Release QuadcastRGB2App

The direct-download release process follows Shotglass: Apple Silicon, macOS 26+,
Developer ID, hardened runtime, app notarization/stapling, then DMG
notarization/stapling. The embedded hidapi library is signed before the app, and
both use the same identity. Library validation stays enabled. Homebrew is a
build dependency only.

CI runs on pushes to **master** and pull requests and uploads an ad-hoc preview DMG.
This project distributes DMGs on GitHub; there is no App Store submission workflow. **Release signed DMG** is
manually dispatched on master. It produces a downloadable artifact by default;
`create_draft_release=true` also prepares a draft GitHub release. Publishing a
draft remains a separate review step. No ordinary push publishes a release or
starts Apple's notarization queue.

## Version and prerequisites

Update every `MARKETING_VERSION` in
`QuadcastRGBApp/QuadcastRGBApp.xcodeproj/project.pbxproj` to the same numeric
`x.y.z`. `python3 scripts/version.py` rejects inconsistent configurations.
Increment `CURRENT_PROJECT_VERSION` for a new build.

Build on an Apple Silicon Mac using Xcode 26+. Install:

```sh
brew install hidapi pkg-config libusb
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install 'dmgbuild==1.6.7'
```

## Local signed release

Use a Developer ID Application certificate and a notarytool keychain profile.
No certificate or password is auto-selected. The default expected signing team
is Paraply Ventures AS (`93627F7C77`), matching Shotglass. If a different team is
intended, explicitly set `REQUIRED_TEAM_ID`.

```sh
export SIGNING_IDENTITY='Developer ID Application: Paraply Ventures AS (93627F7C77)'
export NOTARY_PROFILE=quadcast-paraply
# Optional when credentials live in a dedicated keychain:
export SIGNING_KEYCHAIN=/absolute/path/to/signing.keychain-db
export NOTARY_KEYCHAIN="$SIGNING_KEYCHAIN"
bash scripts/release.sh
```

Provision the profile with `xcrun notarytool store-credentials`, using an App Store
Connect API key or Apple ID credentials. Keep keys and passwords outside the
repository. The existing Shotglass profile/keychain may be used locally by
setting `NOTARY_PROFILE`/`NOTARY_KEYCHAIN` to its actual names; credentials are not
copied by the build scripts.

Output:

- `dist/release/QuadcastRGB2S-<version>-AppleSilicon.dmg`
- `dist/release/SHA256SUMS.txt`
- Public submission/status JSON files for troubleshooting.

The final DMG only appears after the app and DMG have been accepted, stapled and
validated, strict signatures pass, and Gatekeeper accepts both. Existing final
DMGs are never overwritten. Preview packages live under `dist/preview` and are
not release artifacts.

## GitHub Actions secrets

Set these repository secrets in `mscno/QuadcastRGB2S`:

| Secret | Value |
| --- | --- |
| `CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID certificate and private key export |
| `CERTIFICATE_PASSWORD` | Password protecting that P12 |
| `SIGNING_IDENTITY` | Full Developer ID Application identity above |
| `NOTARY_API_KEY_BASE64` | Base64-encoded App Store Connect `.p8` key |
| `NOTARY_KEY_ID` | API key ID |
| `NOTARY_ISSUER_ID` | API issuer UUID |

These match Shotglass's secret names. The App Store Connect API key is used only
for Apple notarization (Gatekeeper), not App Store distribution. Secret values cannot be read back from
GitHub; provision them from the original signing assets or organization secrets.
The runner imports them into a temporary keychain, masks its random password,
and deletes the keychain and key files even on failure. Only the verified DMG,
checksum, and public failure diagnostics are uploaded.

```sh
gh workflow run release.yml --repo mscno/QuadcastRGB2S --ref master
# Add -f create_draft_release=true when preparing a draft.
```

## Validation and review

Before dispatching:

```sh
make test-sanitize
swift test --arch arm64
python3 -m unittest discover -s tests/release -v
```

The workflow also runs native UI tests. CI's `macOS-UI-test-results` artifact
contains the xcresult bundle with screenshots. Review light/dark appearance,
Reduce Transparency, Increase Contrast, Reduce Motion, keyboard navigation,
all six modes, custom color picking, ten-color palettes, narrow window resizing,
permission denied, unplug/replug, reconnect during animation, and launch at login.
Device protocol tests use a mocked HID backend; a real QuadCast 2S remains the
final hardware smoke test before publishing.

If Apple times out, the submission ID/status are preserved. A timeout never
triggers a new submission automatically. Check that existing ID using
`notarytool info`/`log` with the same profile before rebuilding or resubmitting.
There is no final distributable DMG until status is `Accepted`.
