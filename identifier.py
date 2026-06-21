"""
Game identification from a photo of the box.

Current strategies (in priority order):
1. OCR on the image to extract prominent text (title), then fuzzy match against BGG.
2. Direct BGG search by user-provided or corrected name.
3. (Future) CLIP / vision embedding similarity.
4. Manual selection from search results.

For best results on box photos:
- Good lighting, straight-on photo of the front of the box.
- The game title is usually the largest / most prominent text.
"""

import io
from typing import List, Dict, Optional, Tuple
from rapidfuzz import process, fuzz

try:
    from PIL import Image
except ImportError:
    Image = None

# Optional OCR - user can install tesseract + pytesseract
try:
    import pytesseract
    HAS_TESSERACT = True
except ImportError:
    HAS_TESSERACT = False

from bgg_client import search_games


def load_image(uploaded_file) -> Optional[Image.Image]:
    """Load image from Streamlit upload or camera bytes."""
    if uploaded_file is None:
        return None
    if Image is None:
        raise RuntimeError("Pillow is required. Install from requirements.txt")
    if isinstance(uploaded_file, (bytes, bytearray)):
        return Image.open(io.BytesIO(uploaded_file)).convert("RGB")
    # Streamlit UploadedFile has .getvalue() or can be read
    try:
        return Image.open(uploaded_file).convert("RGB")
    except Exception:
        data = uploaded_file.getvalue() if hasattr(uploaded_file, "getvalue") else uploaded_file
        return Image.open(io.BytesIO(data)).convert("RGB")


def extract_text_with_ocr(image: Image.Image) -> str:
    """Run OCR. Returns concatenated text (best effort)."""
    if not HAS_TESSERACT:
        return ""

    try:
        # Preprocess lightly for better box title recognition
        img = image.convert("L")  # grayscale
        text = pytesseract.image_to_string(img, config="--psm 6")
        return text.strip()
    except Exception:
        return ""


def find_title_candidates(ocr_text: str) -> List[str]:
    """Heuristic: pull out likely title lines from OCR garbage."""
    if not ocr_text:
        return []

    lines = [l.strip() for l in ocr_text.splitlines() if l.strip()]
    # Keep longer lines (titles tend to be prominent)
    candidates = [l for l in lines if len(l) > 3]
    # Sort by length descending, take top ones
    candidates.sort(key=len, reverse=True)
    return candidates[:6]


def identify_from_image(image: Image.Image, top_n: int = 5) -> List[Dict]:
    """
    Try to identify the game from a box photo.
    Returns list of BGG candidate dicts with match score.
    """
    results = []

    # 1. OCR path
    ocr_text = extract_text_with_ocr(image)
    title_candidates = find_title_candidates(ocr_text)

    seen_ids = set()

    for candidate in title_candidates:
        bgg_matches = search_games(candidate, limit=3)
        for match in bgg_matches:
            if match["id"] in seen_ids:
                continue
            seen_ids.add(match["id"])
            # Score using fuzzy on the OCR candidate vs BGG name
            score = fuzz.WRatio(candidate, match["name"])
            results.append({
                **match,
                "match_score": score,
                "matched_via": f"OCR: '{candidate}'",
            })

    # 2. If we have very few results, also try common short phrases
    if len(results) < 2 and ocr_text:
        # Try the first 30 chars as a query
        short = ocr_text[:40].strip()
        if short:
            extra = search_games(short, limit=3)
            for m in extra:
                if m["id"] not in seen_ids:
                    seen_ids.add(m["id"])
                    results.append({
                        **m,
                        "match_score": 55,
                        "matched_via": "OCR fragment",
                    })

    # Sort by match quality
    results.sort(key=lambda x: x.get("match_score", 0), reverse=True)
    return results[:top_n]


def identify_by_name(name: str, top_n: int = 6) -> List[Dict]:
    """Simple search by exact or partial name (user typed or corrected)."""
    if not name:
        return []
    matches = search_games(name, limit=top_n)
    for m in matches:
        m["match_score"] = 90 if name.lower() in m["name"].lower() else 70
        m["matched_via"] = "name search"
    return matches


def best_guess(candidates: List[Dict]) -> Optional[Dict]:
    """Pick the highest scoring candidate."""
    if not candidates:
        return None
    return max(candidates, key=lambda c: c.get("match_score", 0))


if __name__ == "__main__":
    print("Identifier module ready.")
    print("Has Tesseract OCR:", HAS_TESSERACT)
    print("Example search:", identify_by_name("wingspan")[:2])
