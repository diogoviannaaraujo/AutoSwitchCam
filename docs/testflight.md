# GitHub Actions and TestFlight

[Release workflow](../.github/workflows/release.yml) runs on every push to `main`,
pull request, and manual dispatch. It uses the same `xcode-27` Apple Silicon runner
as Lightray and pins Tuist to 4.110.3, including its download checksum.

Validation runs the core Swift tests and release-tooling tests, then archives the
app and embedded camera system extension. Pull requests do not receive Apple
signing credentials or upload builds. Archives and test results are retained for
7 days. On `main`, the distribution job signs the archive, creates a signed Mac
App Store installer, uploads it, and waits up to 30 minutes for Apple's processing.
Installer artifacts are retained for 14 days, including if upload or processing
fails. Apple processing failures, missing export compliance, and timeouts fail CI.

Each build uses `(source build + GITHUB_RUN_NUMBER).GITHUB_RUN_ATTEMPT` for both the
app and camera extension. This starts above existing development builds and keeps
versions increasing when macOS replaces an installed extension. Marketing
versions come from `Project.swift`. Release runs are queued
and never cancel a distribution already in progress.

## Apple account setup

The project uses team `W76LFH4CZ4` and these identifiers:

| Target | Bundle ID | Capability |
| --- | --- | --- |
| App | `com.diogoviannaaraujo.AutoSwitchCam` | System Extension installation |
| Camera extension | `com.diogoviannaaraujo.AutoSwitchCam.CameraExtension` | App Groups |

The extension's app group and Mach service use
`W76LFH4CZ4.com.diogoviannaaraujo.AutoSwitchCam.CameraExtension`.
Both executables enable App Sandbox. The app also requests camera access.

The workflow registers missing bundle IDs/capabilities and creates or reuses Mac
App Store profiles for its imported Apple Distribution certificate. It validates
each profile's platform, expiration, team, bundle ID, distribution type, and
certificate before signing the nested framework, extension, and finally app.
The Lightray provisioning profiles cannot be reused because their bundle IDs differ.

Create a **macOS** app named **AutoSwitchCam** in
[App Store Connect](https://appstoreconnect.apple.com/apps), using the app bundle
ID above, English (U.S.) as the primary language, and `AutoSwitchCam-macOS` as SKU.
Apple requires creating this record on its website. The CI provisioning step can
register the bundle IDs before the record exists, then reports that the app
record is needed. After creating it, rerun the failed distribution job.

Create an internal TestFlight group in App Store Connect and enable automatic
distribution if you want each processed build assigned to that group. A build
ready to assign to testers or already in internal testing passes the processing
check; external beta review is separate.

## Repository secrets

Configure these in **Settings → Secrets and variables → Actions** for
`diogoviannaaraujo/AutoSwitchCam`. The names match Lightray so the existing Apple
identities and API key can be reused. Secret values must be transferred securely
from their original files or credential store; GitHub never returns saved values.

| Secret | Value |
| --- | --- |
| `IOS_DISTRIBUTION_P12` | Base64 `.p12` containing the Apple Distribution certificate and private key; this certificate also signs macOS apps |
| `IOS_DISTRIBUTION_PASSWORD` | Its `.p12` export password |
| `MACOS_INSTALLER_P12` | Base64 `.p12` containing the Mac Installer Distribution certificate and private key |
| `MACOS_INSTALLER_PASSWORD` | Its `.p12` export password |
| `APPLE_NOTARY_KEY` | App Store Connect API `.p8` contents, despite the historical secret name |
| `APPLE_NOTARY_KEY_ID` | API key ID |
| `APPLE_NOTARY_ISSUER_ID` | API issuer ID |

The API key needs access to AutoSwitchCam and Certificates, Identifiers & Profiles.
Signing assets are temporary, excluded from Git, and removed by the job's cleanup
step. Keep the matching certificate/private key available when renewing profiles.

To validate without signing or uploading, manually run **Release** and uncheck
**testflight**. Pushes to `main` always attempt distribution after validation.

## Local verification

```bash
tuist generate --no-open
python3 -m unittest discover -s scripts/tests
xcodebuild test -workspace AutoSwitchCam.xcworkspace -scheme AutoSwitchCore \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/ci-tests CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
xcodebuild archive -workspace AutoSwitchCam.xcworkspace -scheme AutoSwitchCam \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath .build/AutoSwitchCam.xcarchive CODE_SIGNING_ALLOWED=NO
```
