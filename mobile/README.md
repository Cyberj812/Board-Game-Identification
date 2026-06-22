# BoardGameSnap - Mobile (Flutter)

Cross-platform mobile app (iOS + Android) for identifying board games from box photos and getting everything you need to play.

## Features (Implemented / Planned)

- Take photo or pick from gallery
- On-device OCR (Google ML Kit)
- Search BGG + smart suggestions
- Rich game detail: stats, expansions, videos, strategy, rules
- Popular games quick access
- Strategy prompt ready for any LLM

## Getting Started

### 1. Install Flutter (if not already)

```bash
# macOS
brew install --cask flutter

# Add to PATH (add to ~/.zshrc)
export PATH="$HOME/flutter/bin:$PATH"

flutter doctor
```

Follow instructions for Xcode (iOS) and/or Android Studio.

### 2. Download Pre-built APK (no Flutter needed)

The easiest way:

1. Go to https://github.com/Cyberj812/Board-Game-Identification/actions
2. Open the latest "Build Android APK" run
3. Download the **board-game-snap-debug** artifact

This gives you the latest `app-debug.apk` with all current features.

### 3. Build locally (if you have Flutter)

```bash
cd mobile
flutter pub get
flutter run
```

Or for APK:

```bash
flutter build apk --debug
# or --release
```

### 4. (Recommended) Add BGG Token for best data

In the app (future Settings screen) or we can add secure storage for a personal BGG API token from https://boardgamegeek.com/applications

## Project Structure

```
mobile/
├── lib/
│   ├── main.dart
│   ├── models/
│   ├── services/       # BGG + OCR
│   └── ...
├── android/
├── ios/
├── windows/            # Desktop support added
├── linux/
├── macos/
├── web/
└── pubspec.yaml
```

## Roadmap / Next Steps

- [ ] Secure storage + settings for BGG token
- [ ] Local history of scanned games
- [ ] Better OCR title extraction heuristics
- [ ] On-device image embeddings / better vision identification
- [ ] Offline support with cached popular games
- [ ] Theming and polish
- [ ] Publish to App Store + Play Store
- [ ] Customized list making (create and manage personal game lists)
- [ ] Snap photo of your collection and auto-build list from photo contents (multi-game detection)
- [ ] Manual entries (add games manually without photo)
- [ ] Illegal move tracker (take photo of game in progress to detect/flag illegal moves)
- [ ] Digital availability section (show if a game can be played digitally and on which platforms, e.g. Board Game Arena, Tabletop Simulator, Steam, etc.)
- [ ] In-app bug submission / feedback tab or "Contact Us" section for reporting issues and suggesting improvements

## Feedback

Found a bug or want to suggest an improvement?

→ [Open an Issue](https://github.com/Cyberj812/Board-Game-Identification/issues/new/choose)

This complements the original Python/Streamlit web prototype.
