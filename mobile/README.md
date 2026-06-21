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
│   ├── models/game.dart
│   ├── services/
│   │   ├── bgg_service.dart
│   │   └── ocr_service.dart
│   └── screens/
│       ├── home_screen.dart
│       └── game_detail_screen.dart
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

This complements the original Python/Streamlit web prototype.
