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

### 2. Get dependencies & run

```bash
cd mobile
flutter pub get
flutter run
```

### 3. (Recommended) Add BGG Token for best data

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

This complements the original Python/Streamlit web prototype.
