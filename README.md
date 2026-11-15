# WatchTrack

WatchTrack is a responsive movie and TV-show tracker built with HTML, CSS, and JavaScript, with Android WebView and iOS WKWebView wrappers. It uses [The Movie Database (TMDB)](https://www.themoviedb.org/) for catalogue metadata, artwork, cast and crew, and streaming-provider availability.

> **Project status:** personal project / test build. The APK in `release/` is a debug build for testing, not a Play Store release.

## Screenshots

The GitHub Actions workflow generates screenshots of the app interface and stores them under `docs/screenshots/`. Use demo data for screenshots so no TMDB token or personal watch history is exposed.

## Features

- A considered visual system with system typography, restrained chartreuse accents, clear hierarchy, and layouts tuned for desktop and phone screens.

- Home dashboard with Continue Watching, movie wishlist, and tracking statistics.
- Separate watched movie and TV libraries with full-library views.
- Episode-level tracking, season accordions, and a confirmation prompt when marking earlier episodes watched.
- Separate movie and TV watch-time totals.
- TMDB-powered search, title details, cast and crew, and streaming-provider availability by country.
- A focused cinematic interface with responsive mobile navigation, accessible controls, reduced-motion support, and lightweight interaction feedback.
- Local browser or Android WebView storage for tracking state. Browser data and Android-app data are separate.

## Run the website

1. Clone or download the repository.
2. Run from the repository root:

   ```bash
   python -m http.server 8000 --directory web
   ```

3. Open `http://localhost:8000`, select **TMDB Setup**, and enter your own TMDB API Read Access Token.
4. Choose the streaming-provider country code (for example `IN`, `US`, or `GB`) and save.

Website source: [`web/`](web/). Android source: [`WatchTrack-Android/`](WatchTrack-Android/). The downloadable source archive is [`WatchTrack-Source.zip`](WatchTrack-Source.zip).

## Install the Android test APK

Download [`release/WatchTrack-debug.apk`](release/WatchTrack-debug.apk) on your Android device and install it. Android may ask you to allow installation from the browser or file manager used for the download.

On first launch, select **TMDB Setup**, enter your TMDB API Read Access Token, set your provider country code, and save. This is a debug/test build, not a Play Store release. Internet access is needed for current TMDB data and streaming availability.

## Install the iPhone test app

The iOS build is published at [`release/WatchTrack-unsigned.ipa`](release/WatchTrack-unsigned.ipa) when Apple signing secrets have not been configured. **An unsigned IPA is not directly installable by tapping it.** Use a sideloading tool such as Sideloadly on a Windows or Mac computer to sign it with your own Apple ID during installation. A free Apple ID requires periodic re-signing; a paid Apple Developer account can be used for longer-lived Ad Hoc builds.

For a directly installable Ad Hoc IPA, register your iPhone in your Apple Developer account, create an Apple Distribution certificate and an Ad Hoc provisioning profile for bundle ID `com.watchtrack.app.ios`, then add these GitHub Actions repository secrets: `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_PROVISIONING_PROFILE_BASE64`, and `APPLE_TEAM_ID`. Never put signing credentials in source files or chat. With those secrets present, the iOS workflow exports `release/WatchTrack-adhoc.ipa`.

The iOS app bundles the same website, stores its TMDB token and tracking data in the app's local WebKit storage, and uses the iOS share sheet for backup export. The iOS shell targets iOS 16 and later. Real-iPhone behavior still needs device testing.


## Build Android from source

Requirements: Java 17, Android SDK platform 35, and Gradle 8.9 (or a compatible Android Studio installation).

```bash
mkdir -p WatchTrack-Android/app/src/main/assets/www
cp web/* WatchTrack-Android/app/src/main/assets/www/
cd WatchTrack-Android
gradle assembleDebug
```

The APK output is `WatchTrack-Android/app/build/outputs/apk/debug/app-debug.apk`. GitHub Actions can build a fresh APK from the source archive; the generated APK is also uploaded as a workflow artifact.

## Repository layout

- `web/` — website HTML, CSS, JavaScript, and website README.
- `WatchTrack-Android/` — Android WebView wrapper source and Gradle configuration.
- `WatchTrack-iOS/` — native SwiftUI/WKWebView wrapper and XcodeGen project specification.
- `WatchTrack-Source.zip` — source bundle with its own top-level README and component documentation.
- `release/WatchTrack-debug.apk` — latest published debug APK.
- `docs/screenshots/` — README screenshots.
- `.github/workflows/build-apk.yml` — automated Android build workflow.
- `.github/workflows/build-ios.yml` — automated iOS IPA build workflow.

## Security and attribution

- Do not commit a TMDB token. Tokens should be entered through **TMDB Setup** and are stored in browser local storage or the Android app's WebView storage.
- Never include a real token or private watch history in screenshots. The token is sent directly to TMDB for API requests.
- For a production public deployment, put private credentials behind a backend/proxy rather than exposing them in frontend code.
- WatchTrack uses the TMDB API but is **not endorsed or certified by TMDB**. Streaming availability data is supplied by JustWatch via TMDB.


## Development standards

Contributions and future UI work follow the project rules in [`AGENTS.md`](AGENTS.md) and [`docs/ENGINEERING_STANDARDS.md`](docs/ENGINEERING_STANDARDS.md). These link to and distill the requested [Apple Design Skill](https://github.com/dickwu/apple-design-skill) and [Emil Kowalski's design-engineering skills](https://github.com/emilkowalski/skills). The rules cover accessibility, responsive behavior, mobile WebView details, purposeful and performant motion, edge-case testing, and release hygiene.
