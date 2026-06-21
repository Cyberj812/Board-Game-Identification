"""
Small built-in dataset for the most popular games.
This makes the app instantly useful even when BGG scraping is being difficult.
"""

POPULAR_DATA = {
    "266192": {  # Wingspan
        "id": "266192",
        "name": "Wingspan",
        "year": "2019",
        "min_players": 1,
        "max_players": 5,
        "playtime": "40–70",
        "min_age": "10",
        "weight": 2.4,
        "rank": 38,
        "image": "https://cf.geekdo-images.com/3l3g4s3n4d3v4k5j6h7g8f9e/image.jpg",  # placeholder-ish
        "categories": ["Animals", "Card Game", "Educational"],
        "mechanics": ["Engine Building", "Hand Management", "Set Collection"],
        "expansions": [
            {"id": "290448", "name": "Wingspan: European Expansion"},
            {"id": "300580", "name": "Wingspan: Oceania Expansion"},
            {"id": "366161", "name": "Wingspan Asia"},
        ],
    },
    "291457": {  # Dune Imperium
        "id": "291457",
        "name": "Dune: Imperium",
        "year": "2020",
        "min_players": 1,
        "max_players": 4,
        "playtime": "60–120",
        "min_age": "14",
        "weight": 3.0,
        "rank": 25,
        "categories": ["Economic", "Fighting", "Science Fiction"],
        "mechanics": ["Deck Building", "Worker Placement"],
        "expansions": [
            {"id": "359097", "name": "Dune: Imperium – Rise of Ix"},
            {"id": "408765", "name": "Dune: Imperium – Uprising"},
        ],
    },
    "13": {
        "id": "13",
        "name": "Catan",
        "year": "1995",
        "min_players": 3,
        "max_players": 4,
        "playtime": "60–120",
        "min_age": "10",
        "weight": 2.3,
        "rank": 400,
        "categories": ["Economic", "Negotiation"],
        "mechanics": ["Dice Rolling", "Hand Management", "Trading"],
        "expansions": [
            {"id": "280", "name": "Catan: 5-6 Player Extension"},
            {"id": "231", "name": "Catan: Seafarers"},
            {"id": "232", "name": "Catan: Cities & Knights"},
        ],
    },
}
