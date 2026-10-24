# iPod Classic Player

A nostalgic media player that recreates the iPod Classic (7th generation) experience on modern phones — silver body, white Click Wheel you actually rotate with your finger, and a small screen with the classic menu.

Built with **Flutter** — one codebase for both **iOS and Android**.

## Features

- 🎵 **Music** — import audio files from your device and play them
- 🔒 **Background playback** — music keeps playing with the screen locked or the app in the background
- 🏝️ **Lock screen / Dynamic Island / Android notification controls** — play, pause, seek, skip from the system Now Playing controls (Dynamic Island on iPhone 14 Pro and newer, via iOS Now Playing)
- 🎛️ **Click Wheel** — rotate to scroll, tap MENU / ⏮ / ⏭ / ⏯ on the wheel, press the center button to select
- 🎬 **Videos** — import and watch video files (`.mp4` / `.mov` recommended) inside the iPod screen
- 🖼️ **Photos** — import and browse photos, rotate the wheel to move between them
- 🎚️ **Seek bar** — drag to scrub through the current track

## Download

- **Android:** download `app-release.apk` from the [Releases](../../releases) page and install it.
- **iPhone:** iOS does not allow installing apps directly from GitHub. Build it yourself with Xcode (steps below), or use a free Apple ID — note the app expires after 7 days on a free provisioning profile.

## Build it yourself

Requirements: Flutter SDK, Xcode (for iOS), Android Studio (for Android), CocoaPods (for iOS).

```bash
flutter create ipod_classic   # if starting from scratch
# replace pubspec.yaml and lib/main.dart with the files in this repo,
# then apply the iOS/Android config described in HUONG_DAN_TUNG_BUOC.md
flutter pub get
flutter run
```

Key configuration (this is what makes background playback work):

- **iOS** — add `UIBackgroundModes: [audio]` to `ios/Runner/Info.plist`
- **Android** — register the `AudioService` service + `MediaButtonReceiver` in `AndroidManifest.xml` and make `MainActivity` extend `AudioServiceActivity`

## Known limitations (v1)

- The imported file list is kept in memory only — restart the app and you import again (persistent library is planned for v2)
- `.mkv` videos are usually not supported by the native players — use `.mp4`
- HEIC photos may not display on Android

## How this project was made — full transparency

I am a first-year student and a beginner programmer. This app was created **with extensive help from an AI assistant (Muse, by Meta)**: the AI proposed the architecture (Flutter + `just_audio` / `just_audio_background`), wrote the code in this repository, and wrote the step-by-step guide that I followed to set up the tools, configure iOS/Android background audio, run, test, and publish the app.

I am publishing the code and this process openly because I wanted to experience what it feels like to ship a real app as an indie developer — and to learn by running, testing, breaking, and fixing something real. Every commit, error, and fix is part of that learning journey.

If you spot a bug or want to improve the Click Wheel, pull requests are welcome.

## License

MIT — do whatever you like with it, just keep the notice.
