# WatchTrack iOS

Native SwiftUI shell for the shared WatchTrack website, rendered in `WKWebView`.

## What it includes

- The same home, Discover, profile, TMDB search, title details, episode tracking, and watch-history screens as the website and Android app.
- A small static-file server bound only to `127.0.0.1:8765`. It serves the bundled `Resources/www` files and gives WebKit a stable origin, so local tracking data and the TMDB token persist across launches.
- iOS safe-area handling, back/forward swipe gestures, native JavaScript alert/confirm dialogs, Safari handoff for external links, and a native share sheet for JSON backup export.
- JSON backup import through the iOS file picker provided by `WKWebView`.

The app does not bundle a TMDB token. On first launch, open **TMDB Setup** and enter your own TMDB API Read Access Token.

## Build locally

Requirements: macOS, Xcode 16 or later, Swift 5, and XcodeGen.

From the repository root:

```bash
brew install xcodegen
rsync -a --delete web/ WatchTrack-iOS/WatchTrack/Resources/www/
swift scripts/generate-ios-app-icon.swift WatchTrack-iOS/WatchTrack/Assets.xcassets/AppIcon.appiconset/AppIcon.png
cd WatchTrack-iOS
xcodegen generate --spec project.yml
xcodebuild -project WatchTrack.xcodeproj -scheme WatchTrack -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

The app bundle is created under Xcode's DerivedData `Build/Products/Release-iphoneos/WatchTrack.app`.

## IPA signing and installation

The GitHub Actions workflow builds an unsigned IPA by default. An unsigned IPA is an archive for sideloading tools; iOS will not install it directly from Files or Safari.

- **Personal testing without a paid developer membership:** use Sideloadly (Windows or macOS) or another reputable sideloading tool to sign the unsigned IPA with your own Apple ID during installation. Free-account signatures need periodic renewal.
- **Direct Ad Hoc installation:** requires an Apple Developer Program membership, an Apple Distribution certificate, an Ad Hoc provisioning profile for `com.watchtrack.app.ios`, and the target iPhone's UDID registered in that profile.

To enable Ad Hoc signing in GitHub Actions, add these repository secrets under **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_BASE64` | Base64-encoded Apple Distribution `.p12` certificate |
| `APPLE_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` file |
| `APPLE_PROVISIONING_PROFILE_BASE64` | Base64-encoded Ad Hoc `.mobileprovision` profile |
| `APPLE_TEAM_ID` | Your 10-character Apple Developer Team ID |

The workflow imports the certificate into a temporary macOS keychain, installs the profile, exports a signed Ad Hoc IPA, and removes the temporary signing material. Do not commit certificates, profiles, passwords, or TMDB tokens.

For a signed build, download `release/WatchTrack-adhoc.ipa`. Without those secrets, download `release/WatchTrack-unsigned.ipa` and sign it on your own computer with your Apple ID.

## Security notes

- The local asset server binds to IPv4 loopback only; it is not exposed to the Wi-Fi or cellular network.
- App Transport Security is relaxed only for local networking. TMDB and artwork requests continue to use HTTPS.
- The WebKit origin and port remain fixed to preserve the app's local storage.
- The JavaScript bridge exposes only the backup-export action; external pages open in Safari instead of being loaded into the privileged app WebView.

This is a personal test build, not an App Store submission. The app has not been manually tested on a physical iPhone yet.
