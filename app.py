"""
BoardGameSnap - Identify a board game from a box photo and get everything you need.

Features:
- Camera or photo upload
- Automatic (OCR + search) + manual identification
- BGG rank, weight, player count, playtime
- Expansions list
- Curated "How to Play" video links
- Strategy hints
- Rulebook / files links
"""

import streamlit as st
from PIL import Image
import io
import datetime

from bgg_client import (
    get_game_details,
    get_player_count_str,
    get_weight_str,
    get_rank_str,
    get_expansions,
    POPULAR_GAMES,
    BGG_TOKEN,
)
from identifier import (
    load_image,
    identify_from_image,
    identify_by_name,
    best_guess,
    HAS_TESSERACT,
)


def _make_summary_text(name, details, expansions):
    lines = [
        f"{name} ({details.get('year', '')})",
        f"Players: {get_player_count_str(details)}",
        f"Weight: {get_weight_str(details)}",
        f"BGG Rank: {get_rank_str(details)}",
        "",
        "Expansions:",
    ]
    for e in expansions:
        lines.append(f"  - {e['name']}")
    lines.append("")
    lines.append("BGG page: " + f"https://boardgamegeek.com/boardgame/{details.get('id', '')}")
    return "\n".join(lines)


st.set_page_config(
    page_title="BoardGameSnap",
    page_icon="🎲",
    layout="wide",
    initial_sidebar_state="expanded",
)

st.title("🎲 BoardGameSnap")
st.caption("Point your camera at a board game box → get videos, strategy, rules, expansions & BGG stats")

# ---------------- Sidebar ----------------
with st.sidebar:
    st.header("How to use")
    st.markdown("""
    1. Take or upload a clear photo of the **front of the box**.
    2. Review the suggested game(s) and pick the correct one.
    3. Explore videos, strategy tips, rulebook, and expansions.
    """)

    st.divider()
    st.subheader("Identification quality")
    if HAS_TESSERACT:
        st.success("OCR enabled (tesseract)")
    else:
        st.info("OCR disabled. Install tesseract for better auto-detection:\n`brew install tesseract` then `pip install pytesseract`")

    st.divider()
    st.caption("Data from BoardGameGeek • Videos from YouTube")
    if not BGG_TOKEN:
        st.warning("For the most reliable data, set a BGG token:\nhttps://boardgamegeek.com/applications\nThen `export BGG_TOKEN=...` before running the app.")
    else:
        st.success("Using authenticated BGG access")

    if st.button("Clear cache"):
        st.cache_data.clear()
        st.rerun()

# ---------------- Main input ----------------
col1, col2 = st.columns([1, 1.1])

with col1:
    st.subheader("📸 Capture or Upload Box")

    camera_photo = st.camera_input("Take a photo of the game box", key="camera")
    uploaded = st.file_uploader(
        "Or upload a photo",
        type=["jpg", "jpeg", "png", "webp"],
        key="upload",
    )

    image = None
    source = None
    if camera_photo is not None:
        image = camera_photo
        source = "camera"
    elif uploaded is not None:
        image = uploaded
        source = "upload"

    if image:
        pil_img = load_image(image)
        st.image(pil_img, caption="Your photo", use_column_width=True)

with col2:
    st.subheader("🔍 Identify the Game")

    if image:
        with st.spinner("Analyzing photo..."):
            candidates = identify_from_image(load_image(image))

        if candidates:
            st.write("**Top matches from photo:**")
            for i, c in enumerate(candidates):
                label = f"{c['name']} ({c.get('year', '')}) — score {c.get('match_score', 0)}"
                if st.button(label, key=f"pick_ocr_{i}"):
                    st.session_state.selected_game = c
                    st.rerun()
        else:
            st.info("No strong matches from the photo. Try typing the name below or retake with better lighting.")

    # Manual / correction search
    st.divider()
    manual_name = st.text_input(
        "Search by name (or correct the guess)",
        placeholder="e.g. Wingspan, Dune Imperium, Brass Birmingham",
        key="manual_search",
    )

    if manual_name:
        manual_candidates = identify_by_name(manual_name)
        if manual_candidates:
            st.write("**Search results:**")
            for i, c in enumerate(manual_candidates):
                label = f"{c['name']} ({c.get('year', '')})"
                if st.button(label, key=f"pick_manual_{i}"):
                    st.session_state.selected_game = c
                    st.rerun()

    # Quick popular games (very reliable)
    st.divider()
    st.caption("Or pick a popular game instantly:")
    pop_cols = st.columns(5)
    for idx, pg in enumerate(POPULAR_GAMES[:10]):
        with pop_cols[idx % 5]:
            if st.button(pg["name"], key=f"pop_{pg['id']}"):
                st.session_state.selected_game = pg
                st.rerun()

# ---------------- Results Section ----------------
if "selected_game" in st.session_state:
    game = st.session_state.selected_game
    game_id = game["id"]
    name = game["name"]

    st.divider()
    st.header(f"📦 {name} ({game.get('year', '')})")

    # Fetch full details
    with st.spinner("Loading game data from BoardGameGeek..."):
        details = get_game_details(game_id)

    if not details:
        st.error("Failed to load details from BGG. The game may have been deleted or BGG is slow.")
        st.stop()

    # Key stats row
    m1, m2, m3, m4, m5 = st.columns(5)
    m1.metric("Players", get_player_count_str(details))
    m2.metric("Weight", get_weight_str(details), help="Complexity / learning curve (1 = light, 5 = heavy)")
    m3.metric("BGG Rank", get_rank_str(details))
    m4.metric("Playtime", f"{details.get('playtime', '?')} min")
    m5.metric("Age", f"{details.get('min_age', '?')}+")

    # Description
    if details.get("description"):
        with st.expander("Description", expanded=False):
            st.write(details["description"])

    # Image from BGG
    if details.get("image"):
        st.image(details["image"], caption=name, width=420)

    # ---------------- Expansions ----------------
    st.subheader("📦 Expansions")
    expansions = get_expansions(game_id)
    if expansions:
        exp_cols = st.columns(2)
        for idx, exp in enumerate(expansions[:10]):
            with exp_cols[idx % 2]:
                st.markdown(f"- **{exp['name']}** (ID: {exp['id']})")
        if len(expansions) > 10:
            st.caption(f"+ {len(expansions) - 10} more expansions")
    else:
        st.write("No expansions found for this game (or none registered on BGG).")

    # ---------------- How to Play Videos ----------------
    st.subheader("▶️ How to Play Videos")

    slug = name.lower().replace(" ", "+").replace(":", "")
    video_links = [
        (f"Watch It Played – {name}", f"https://www.youtube.com/results?search_query=how+to+play+{slug}+%22watch+it+played%22"),
        (f"Official / Publisher Rules – {name}", f"https://www.youtube.com/results?search_query=how+to+play+{slug}+official"),
        (f"Rules Explained – {name}", f"https://www.youtube.com/results?search_query={slug}+rules+explained"),
        (f"Quick Rules – {name}", f"https://www.youtube.com/results?search_query={slug}+how+to+play+quick"),
        ("Search YouTube for more", f"https://www.youtube.com/results?search_query=how+to+play+{slug}"),
    ]

    for title, url in video_links:
        st.markdown(f"- [{title}]({url})")

    st.caption("Tip: 'Watch It Played' is widely considered the gold standard for clear, high-quality teach videos.")

    # ---------------- Strategy Hints ----------------
    st.subheader("🧠 Strategy Hints & Tips")

    # We provide good starter advice + a ready-to-use LLM prompt
    st.markdown("Here are some general strategic principles. For game-specific deep strategy, use the prompt below with your favorite LLM.")

    # Basic template advice (can be made richer per game later)
    st.markdown("""
    **General advice that applies to most modern board games:**
    - **Engine building first**: Focus on setting up combos before scoring points.
    - **Deny key resources** to opponents when it doesn't cost you too much.
    - **Watch the endgame trigger** — many games are won or lost in the last 2-3 rounds.
    - **Take the 'worst' action** only when it is still better than letting opponents have the good ones.
    """)

    with st.expander("🔥 Copy-paste prompt for strong LLM strategy advice"):
        prompt = f"""You are an expert board game strategist. The game is {name}.

Give me 7 specific, actionable strategy tips suitable for someone who has played the game 3-5 times.

Focus on:
- Opening moves and early game priorities
- Key combos and engines
- Interaction / blocking other players
- Endgame timing and scoring efficiency
- Common mistakes to avoid

Be concrete. Reference specific mechanics when possible. Avoid generic advice like "have fun".
"""
        st.code(prompt, language="markdown")
        st.caption("Paste the above into Grok, Claude, GPT-4o, etc.")

    # ---------------- Rulebook ----------------
    st.subheader("📜 Rulebook & Reference")

    bgg_files = f"https://boardgamegeek.com/boardgame/{game_id}/files"
    bgg_page = f"https://boardgamegeek.com/boardgame/{game_id}"

    st.markdown(f"- [BGG Files page]({bgg_files}) (official rules PDFs, player aids, etc. are often uploaded here)")
    st.markdown(f"- [Full BoardGameGeek page]({bgg_page})")
    st.markdown(f"- [Google: \"{name} official rules PDF\"](https://www.google.com/search?q={slug}+official+rules+pdf)")

    # ---------------- Footer actions ----------------
    st.divider()
    col_a, col_b = st.columns(2)
    with col_a:
        if st.button("🔄 Scan another game"):
            if "selected_game" in st.session_state:
                del st.session_state.selected_game
            st.rerun()

    with col_b:
        st.download_button(
            "Download this summary (text)",
            data=_make_summary_text(name, details, expansions),
            file_name=f"{name.replace(' ', '_')}_summary.txt",
            mime="text/plain",
        )


# ---------------- Footer ----------------
st.divider()
st.caption("Built with ❤️ for board gamers • Data: BoardGameGeek • Your photos never leave your device except for OCR (local)")
st.caption(f"Last updated: {datetime.date.today().isoformat()}")
