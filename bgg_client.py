"""
Robust BoardGameGeek client.

Priority order:
1. Token-authenticated XML API (if BGG_TOKEN env var is set)
2. Public HTML scraping fallback (works without any key)

Get a free token (recommended for reliability):
- Go to https://boardgamegeek.com/applications
- Create a new application
- Copy the access token
- export BGG_TOKEN=your_token_here
"""

import os
import re
import time
import requests
from typing import Optional, List, Dict, Any
from urllib.parse import quote
from bs4 import BeautifulSoup
from static_data import POPULAR_DATA

# ---------------------------
# Configuration
# ---------------------------
BGG_TOKEN = os.getenv("BGG_TOKEN") or os.getenv("BGG_API_TOKEN")
HEADERS_XML = {
    "User-Agent": "BoardGameSnap/0.2 (+https://github.com/Cyberj812/Board-Game-Identification)",
    "Accept": "application/xml",
}
if BGG_TOKEN:
    HEADERS_XML["Authorization"] = f"Bearer {BGG_TOKEN}"

HEADERS_HTML = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Referer": "https://boardgamegeek.com/",
    "Sec-Fetch-Dest": "document",
    "Sec-Fetch-Mode": "navigate",
    "Sec-Fetch-Site": "same-origin",
}

BASE_XML = "https://boardgamegeek.com/xmlapi2"
_last_call = 0.0


def _throttle():
    global _last_call
    now = time.time()
    # BGG asks for politeness — especially important without token
    delay = 0.8 if BGG_TOKEN else 1.8
    if now - _last_call < delay:
        time.sleep(delay - (now - _last_call))
    _last_call = time.time()


def _get(url: str, use_xml_headers: bool = False) -> str:
    _throttle()
    headers = HEADERS_XML if use_xml_headers else HEADERS_HTML
    r = requests.get(url, headers=headers, timeout=20)
    r.raise_for_status()
    return r.text


# ---------------------------
# XML API (when token available)
# ---------------------------

def _xml_search(query: str) -> List[Dict[str, Any]]:
    url = f"{BASE_XML}/search?query={quote(query)}&type=boardgame"
    xml = _get(url, use_xml_headers=True)
    # Simple parsing without heavy deps
    from xml.etree import ElementTree as ET
    root = ET.fromstring(xml)
    out = []
    for item in root.findall("item"):
        gid = item.get("id")
        name = item.find("name")
        year = item.find("yearpublished")
        out.append({
            "id": gid,
            "name": name.get("value") if name is not None else "Unknown",
            "year": year.get("value") if year is not None else "",
        })
    return out


def _xml_details(game_id: str) -> Optional[Dict[str, Any]]:
    url = f"{BASE_XML}/thing?id={game_id}&stats=1"
    xml = _get(url, use_xml_headers=True)
    from xml.etree import ElementTree as ET
    root = ET.fromstring(xml)
    item = root.find("item")
    if item is None:
        return None

    data = _parse_xml_thing(item)
    data["id"] = game_id
    return data


def _parse_xml_thing(item) -> Dict[str, Any]:
    from xml.etree import ElementTree as ET

    def get_attr(tag, attr="value", default=""):
        el = item.find(tag)
        return el.get(attr) if el is not None else default

    data = {
        "name": "",
        "year": get_attr("yearpublished"),
        "min_players": int(get_attr("minplayers") or 0),
        "max_players": int(get_attr("maxplayers") or 0),
        "playtime": get_attr("playingtime"),
        "min_age": get_attr("minage"),
        "image": item.findtext("image", ""),
        "thumbnail": item.findtext("thumbnail", ""),
        "weight": None,
        "rank": None,
        "categories": [],
        "mechanics": [],
        "expansions": [],
    }

    name_el = item.find("name[@type='primary']") or item.find("name")
    if name_el is not None:
        data["name"] = name_el.get("value", "")

    # Stats
    stats = item.find("statistics/ratings")
    if stats is not None:
        w = stats.find("averageweight")
        if w is not None:
            try:
                data["weight"] = float(w.get("value"))
            except:
                pass

        for r in stats.findall("ranks/rank"):
            if r.get("name") == "boardgame":
                v = r.get("value")
                if v and v != "Not Ranked":
                    try:
                        data["rank"] = int(v)
                    except:
                        pass

    # Links
    for link in item.findall("link"):
        ltype = link.get("type")
        val = link.get("value", "")
        if ltype == "boardgamecategory":
            data["categories"].append(val)
        elif ltype == "boardgamemechanic":
            data["mechanics"].append(val)
        elif ltype == "boardgameexpansion" and link.get("inbound") == "true":
            data["expansions"].append({"id": link.get("id"), "name": val})

    return data


# ---------------------------
# HTML scraping fallback (no token needed)
# ---------------------------

def _scrape_search(query: str) -> List[Dict[str, Any]]:
    """Scrape the public BGG search page (more tolerant selectors)."""
    url = f"https://boardgamegeek.com/geeksearch.php?action=search&objecttype=boardgame&q={quote(query)}"
    html = _get(url)
    soup = BeautifulSoup(html, "lxml")

    results = []
    # Try several likely selectors (BGG changes their markup)
    candidates = soup.select("a[href*=\"/boardgame/\"]")
    seen = set()
    for a in candidates:
        href = a.get("href", "")
        m = re.search(r"/boardgame/(\d+)/", href)
        if not m:
            continue
        gid = m.group(1)
        if gid in seen:
            continue
        seen.add(gid)
        name = a.get_text(strip=True).split("(")[0].strip()
        # Try to grab year from nearby text
        parent_text = a.parent.get_text() if a.parent else a.get_text()
        year_match = re.search(r"\((\d{4})\)", parent_text)
        year = year_match.group(1) if year_match else ""
        results.append({"id": gid, "name": name, "year": year})
        if len(results) >= 8:
            break
    return results


def _scrape_game_page(game_id: str) -> Optional[Dict[str, Any]]:
    """Scrape a game page for stats."""
    url = f"https://boardgamegeek.com/boardgame/{game_id}"
    html = _get(url)
    soup = BeautifulSoup(html, "lxml")

    # Title
    title_el = soup.select_one("h1 a") or soup.select_one("h1")
    name = title_el.get_text(strip=True) if title_el else "Unknown"

    # Year
    year = ""
    year_el = soup.select_one("h1 + span, .game-year")
    if year_el:
        year = re.sub(r"[^\d]", "", year_el.get_text())[:4]

    # Stats box
    data = {
        "id": game_id,
        "name": name,
        "year": year,
        "min_players": 0,
        "max_players": 0,
        "playtime": "?",
        "min_age": "?",
        "image": "",
        "thumbnail": "",
        "weight": None,
        "rank": None,
        "categories": [],
        "mechanics": [],
        "expansions": [],
    }

    # Try to find player count, time, etc. (these selectors are fragile but work often)
    stats_text = soup.get_text(" ", strip=True)

    # Players
    m = re.search(r"(\d+)\s*[–-]\s*(\d+)\s*Players?", stats_text, re.I)
    if m:
        data["min_players"] = int(m.group(1))
        data["max_players"] = int(m.group(2))
    else:
        m = re.search(r"(\d+)\s*Players?", stats_text, re.I)
        if m:
            data["min_players"] = data["max_players"] = int(m.group(1))

    # Playtime
    m = re.search(r"(\d+)\s*[–-]\s*(\d+)\s*Min", stats_text, re.I)
    if m:
        data["playtime"] = f"{m.group(1)}–{m.group(2)}"
    else:
        m = re.search(r"(\d+)\s*Min", stats_text, re.I)
        if m:
            data["playtime"] = m.group(1)

    # Weight / Rank often in specific elements
    for el in soup.select(".stats, .game-stats, [class*='weight'], [class*='rank']"):
        txt = el.get_text(" ", strip=True).lower()
        mw = re.search(r"weight[:\s]+([\d.]+)", txt)
        if mw and data["weight"] is None:
            try:
                data["weight"] = float(mw.group(1))
            except:
                pass

        mr = re.search(r"rank[:\s#]*(\d+)", txt)
        if mr and data["rank"] is None:
            try:
                data["rank"] = int(mr.group(1))
            except:
                pass

    # Image (main box image)
    img = soup.select_one("img[alt*='boardgame'], .game-image img, meta[property='og:image']")
    if img:
        src = img.get("content") or img.get("src", "")
        if src.startswith("//"):
            src = "https:" + src
        if src.startswith("/"):
            src = "https://boardgamegeek.com" + src
        data["image"] = src

    # Expansions - look for a section
    for a in soup.select("a[href*='/boardgameexpansion/']"):
        href = a.get("href", "")
        m = re.search(r"/boardgame/(\d+)/", href)
        if m:
            data["expansions"].append({"id": m.group(1), "name": a.get_text(strip=True)})

    # Dedup expansions
    seen = set()
    unique_exp = []
    for e in data["expansions"]:
        if e["id"] not in seen:
            seen.add(e["id"])
            unique_exp.append(e)
    data["expansions"] = unique_exp[:15]

    return data


# ---------------------------
# Public API
# ---------------------------

def search_games(query: str, limit: int = 8) -> List[Dict[str, Any]]:
    """Search for games. Works with or without token."""
    if not query or len(query.strip()) < 2:
        return []

    if BGG_TOKEN:
        try:
            return _xml_search(query)[:limit]
        except Exception:
            pass

    try:
        return _scrape_search(query)[:limit]
    except Exception as e:
        print(f"[BGG] Search failed: {e}")
        # Return empty; app will fall back to popular games + manual entry
        return []


def get_game_details(game_id: str) -> Optional[Dict[str, Any]]:
    """Get rich game data. Falls back to built-in data for popular titles."""
    if BGG_TOKEN:
        try:
            d = _xml_details(game_id)
            if d:
                return d
        except Exception:
            pass

    try:
        d = _scrape_game_page(game_id)
        if d:
            return d
    except Exception as e:
        print(f"[BGG] Scrape failed for {game_id}: {e}")

    # Last resort: built-in data
    if game_id in POPULAR_DATA:
        return POPULAR_DATA[game_id].copy()
    return None


# Popular games for instant selection when live search is flaky
POPULAR_GAMES = [
    {"id": "266192", "name": "Wingspan", "year": "2019"},
    {"id": "174430", "name": "Gloomhaven", "year": "2017"},
    {"id": "291457", "name": "Dune: Imperium", "year": "2020"},
    {"id": "167791", "name": "Terraforming Mars", "year": "2016"},
    {"id": "13", "name": "Catan", "year": "1995"},
    {"id": "169786", "name": "Scythe", "year": "2016"},
    {"id": "205637", "name": "Ark Nova", "year": "2021"},
    {"id": "199792", "name": "Everdell", "year": "2018"},
    {"id": "31260", "name": "Agricola", "year": "2007"},
]


def get_expansions(game_id: str) -> List[Dict[str, str]]:
    d = get_game_details(game_id)
    return d.get("expansions", []) if d else []


def get_player_count_str(d: Dict[str, Any]) -> str:
    minp, maxp = d.get("min_players", 0), d.get("max_players", 0)
    if minp and maxp:
        return f"{minp}–{maxp}" if minp != maxp else str(minp)
    return "?"


def get_weight_str(d: Dict[str, Any]) -> str:
    w = d.get("weight")
    return f"{w:.1f}/5" if w else "?"


def get_rank_str(d: Dict[str, Any]) -> str:
    r = d.get("rank")
    return f"#{r}" if r else "Unranked"


if __name__ == "__main__":
    print("BGG client ready. Token present:", bool(BGG_TOKEN))
    print("\nSearching 'wingspan'...")
    res = search_games("wingspan", 3)
    print(res)

    if res:
        gid = res[0]["id"]
        d = get_game_details(gid)
        print("\nDetails:", d.get("name") if d else None)
        print("Players:", get_player_count_str(d or {}))
        print("Rank/Weight:", get_rank_str(d or {}), get_weight_str(d or {}))
        print("Expansions:", get_expansions(gid)[:3])
