# BoardGameSnap

**Two versions available:**

- **Mobile App (Flutter)** → iOS + Android (recommended for real use)
- **Web Prototype (Streamlit)** → Quick demo / desktop

---

Point your phone or webcam at a board game box and instantly get:

- Accurate identification of the game
- BoardGameGeek rank, weight, player count, play time
- List of available expansions
- High-quality "How to Play" video links (Watch It Played prioritized)
- Strategy hints + ready-to-use prompts for LLMs
- Direct links to rulebooks and player aids

## Features (Current)

- 📸 Camera capture + file upload (works great on desktop + mobile via Streamlit)
- 🔍 OCR-assisted identification (when tesseract is installed) + smart BGG search
- 📊 Full BGG stats (rank, complexity weight, player range)
- 📦 Expansions list pulled live from BGG
- ▶️ Curated how-to-play YouTube searches
- 🧠 Actionable strategy advice + copy/paste LLM prompt
- 📜 Rulebook & reference links

## Repository Structure

```
.
├── mobile/                 # Flutter app (iOS + Android + Desktop + Web)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/
│   │   └── services/       # BGG + OCR
│   ├── android/
│   ├── ios/
│   ├── windows/
│   ├── linux/
│   ├── macos/
│   └── web/
├── app.py                  # Streamlit web prototype
├── bgg_client.py
├── identifier.py
├── requirements.txt
└── README.md
```

## Mobile App (Flutter) - Recommended

```bash
cd mobile
flutter pub get
flutter run
```

See `mobile/README.md` for setup details (requires Flutter SDK).

## Web Prototype (Streamlit)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
streamlit run app.py
```

## BGG Token (for best results)

1. Go to https://boardgamegeek.com/applications
2. Create a free application → copy the token
3. Set `BGG_TOKEN` environment variable when running

## Features

- 📸 Photo of board game box → identification
- 📊 BGG rank, weight, player count, playtime
- 📦 Expansions list
- ▶️ How-to-play video links
- 🧠 Strategy hints + LLM prompts
- 📜 Rulebook links


## Game Identification

Current approach (layered for reliability):
1. Photo → local OCR (tesseract) extracts text → fuzzy search on BGG
2. Strong name search (type or correct the name)
3. One-click popular games
4. User confirmation before showing full results

Future improvements (easy to add):
- Vision embeddings (CLIP) for box art similarity
- Local vision LLM support (Ollama + llava)
- Direct Grok / GPT-4o vision call for identification

**Pro tip**: If scraping is blocked, the app still works great by picking from the Popular list or typing the name.

## Data Sources

- BoardGameGeek XML API 2 (https://boardgamegeek.com/wiki/page/BGG_XML_API2)
- YouTube (search links)
- Local image processing only (your photos don't get uploaded anywhere except for local OCR)

## Future Ideas

- [ ] Persist history of scanned games (SQLite)
- [ ] "Similar games" recommendations
- [ ] Price / availability checking
- [ ] Collection sync (BGG username import)
- [ ] Offline mode with cached popular games
- [ ] Mobile-friendly PWA or native wrapper
- [ ] Better strategy content per game (community tips)
- [ ] Customized list making (create and manage personal game lists)
- [ ] Snap photo of your collection and auto-build list from photo contents (multi-game detection)
- [ ] Manual entries (add games manually without photo)
- [ ] Illegal move tracker (take photo of game in progress to detect/flag illegal moves)

## Mobile App (Flutter)

Full native mobile experience for both platforms.

```bash
cd mobile
flutter pub get
flutter run
```

See [mobile/README.md](mobile/README.md) for details.

Key advantages over the web version:
- On-device OCR (Google ML Kit)
- Native camera experience
- Works great offline for popular games
- Ready for App Store / Play Store distribution

## Web Prototype (Streamlit)

Still useful for quick testing on desktop:

```bash
source .venv/bin/activate
streamlit run app.py
```

## License

This project is licensed under the [MIT License](LICENSE).

## Credits

Built on top of the excellent data at BoardGameGeek.

---

This project was started as the implementation of https://github.com/Cyberj812/Board-Game-Identification goals.
