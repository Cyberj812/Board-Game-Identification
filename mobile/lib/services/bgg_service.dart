import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/game.dart';

class BggService {
  static const String _base = 'https://boardgamegeek.com/xmlapi2';
  final String? token;

  BggService({this.token});

  // DEMO DATA kept only as an ultimate last-resort (currently not used for search/details).
  // Live BGG XML API v2 calls are preferred (token optional for search/details; required for private collection fetches).
  static final List<Game> _demoGames = [
    Game(
      id: '13',
      name: 'Catan',
      year: '1995',
      minPlayers: 3,
      maxPlayers: 4,
      playtime: '60-120',
      weight: 2.3,
      rank: 400,
      rating: 7.2,
      digitalPlatforms: [
        DigitalPlatform(name: 'Tabletop Simulator', url: 'https://store.steampowered.com/app/286160/Tabletop_Simulator/'),
        DigitalPlatform(name: 'Catan Universe (Steam)', url: 'https://store.steampowered.com/app/544730/Catan_Universe/'),
      ],
      expansions: [
        Expansion(id: '11', name: 'Catan: Cities & Knights'),
        Expansion(id: '10', name: 'Catan: Seafarers'),
        Expansion(id: '12', name: 'Catan: Traders & Barbarians'),
      ],
    ),
    Game(
      id: '266192',
      name: 'Wingspan',
      year: '2019',
      minPlayers: 1,
      maxPlayers: 5,
      playtime: '40-70',
      weight: 2.4,
      rank: 38,
      rating: 8.1,
      digitalPlatforms: [
        DigitalPlatform(name: 'Tabletop Simulator', url: 'https://store.steampowered.com/app/286160/Tabletop_Simulator/'),
        DigitalPlatform(name: 'Board Game Arena', url: 'https://boardgamearena.com/'),
      ],
    ),
    Game(
      id: '291457',
      name: 'Dune: Imperium',
      year: '2020',
      minPlayers: 1,
      maxPlayers: 4,
      playtime: '60-120',
      weight: 3.0,
      rank: 25,
      rating: 8.4,
      digitalPlatforms: [
        DigitalPlatform(name: 'Tabletop Simulator', url: 'https://store.steampowered.com/app/286160/Tabletop_Simulator/'),
      ],
    ),
    Game(
      id: '205637',
      name: 'Ark Nova',
      year: '2021',
      minPlayers: 1,
      maxPlayers: 4,
      playtime: '90-150',
      weight: 3.7,
      rank: 4,
      rating: 8.7,
    ),
    Game(
      id: '9209',
      name: 'Ticket to Ride',
      year: '2004',
      minPlayers: 2,
      maxPlayers: 5,
      playtime: '30-60',
      weight: 1.9,
      rank: 220,
      rating: 7.5,
      digitalPlatforms: [
        DigitalPlatform(name: 'Tabletop Simulator', url: 'https://store.steampowered.com/app/286160/Tabletop_Simulator/'),
      ],
    ),
    Game(
      id: '30549',
      name: 'Pandemic',
      year: '2008',
      minPlayers: 2,
      maxPlayers: 4,
      playtime: '45',
      weight: 2.4,
      rank: 250,
      rating: 7.6,
    ),
  ];

  Map<String, String> get _headers {
    final h = {
      'User-Agent': 'BoardGameSnap/1.0 (Flutter App)',
      'Accept': 'application/xml',
    };
    if (token != null && token!.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  String _appendToken(String url) {
    if (token != null && token!.isNotEmpty) {
      final separator = url.contains('?') ? '&' : '?';
      return '$url${separator}token=${Uri.encodeComponent(token!)}';
    }
    return url;
  }

  Future<List<Game>> searchGames(String query, {int limit = 10, int start = 0}) async {
    if (query.trim().length < 2) return [];

    // Live BGG API (token optional for basic public searches and higher rate limits).
    // Collection import requires a valid personal token for the username.
    // Only include start if >0. BGG search pagination is unreliable; omitting for initial searches helps.
    String url = '$_base/search?query=${Uri.encodeComponent(query)}&type=boardgame';
    if (start > 0) url += '&start=$start';
    url = _appendToken(url);
    final uri = Uri.parse(url);

    List<Game> parsed = [];
    int attempt = 0;
    const maxAttempts = 3;

    while (attempt < maxAttempts && parsed.isEmpty) {
      attempt++;
      if (attempt > 1) {
        await Future.delayed(const Duration(milliseconds: 2200));
      }

      http.Response resp;
      try {
        resp = await http.get(uri, headers: _headers);
      } catch (_) {
        continue;
      }

      // Try to parse on any response that has body (BGG can be quirky with status codes)
      if (resp.body.isNotEmpty) {
        try {
          parsed = _parseSearchResults(resp.body, limit);
        } catch (_) {
          parsed = [];
        }
      }

      // If we got something, use it
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }

    // No usable results from live BGG after retries. Return empty (pure BGG data only).
    return [];
  }

  List<Game> _parseSearchResults(String body, int limit) {
    final document = XmlDocument.parse(body);
    final items = document.findAllElements('item');

    final results = <Game>[];
    for (final item in items.take(limit)) {
      final id = item.getAttribute('id') ?? '';
      if (id.isEmpty) continue;

      // Prefer primary name, fall back to first name
      final nameEls = item.findElements('name').toList();
      String name = 'Unknown';
      if (nameEls.isNotEmpty) {
        final primary = nameEls.firstWhere(
          (e) => e.getAttribute('type') == 'primary',
          orElse: () => nameEls.first,
        );
        name = primary.getAttribute('value') ?? 'Unknown';
      }

      final yearEl = item.findElements('yearpublished').firstOrNull;
      final year = yearEl?.getAttribute('value') ?? '';

      results.add(Game(id: id, name: name, year: year));
    }
    return results;
  }

  Future<Game?> getGameDetails(String id) async {
    // Live BGG details. Token is optional (public game info is available unauthenticated).
    // Always try the live BGG API to get complete data (expansions, full stats, etc.)
    try {
      final url = _appendToken('$_base/thing?id=$id&stats=1');
      final uri = Uri.parse(url);
      final resp = await http.get(uri, headers: _headers);

      if (resp.statusCode == 200) {
        final doc = XmlDocument.parse(resp.body);
        final item = doc.findAllElements('item').firstOrNull;
        if (item != null) {
          final parsed = _parseThing(item, id);
          return parsed;
        }
      }
    } catch (_) {
      // No fallback - we want only live BGG data
    }

    return null;
  }

  Game _parseThing(XmlElement item, String id) {
    String getValue(String tag) =>
        item.findElements(tag).firstOrNull?.getAttribute('value') ?? '';

    final primaryName = item
            .findElements('name')
            .firstWhere((e) => e.getAttribute('type') == 'primary',
                orElse: () => item.findElements('name').first)
            .getAttribute('value') ??
        '';

    final stats = item.findElements('statistics').firstOrNull?.findElements('ratings').firstOrNull;

    double? weight;
    int? rank;
    double? rating;
    final weightEl = stats?.findElements('averageweight').firstOrNull;
    if (weightEl != null) weight = double.tryParse(weightEl.getAttribute('value') ?? '');

    final avgEl = stats?.findElements('average').firstOrNull;
    if (avgEl != null) rating = double.tryParse(avgEl.getAttribute('value') ?? '');

    final ranks = stats?.findElements('ranks').firstOrNull?.findElements('rank') ?? [];
    for (final r in ranks) {
      if (r.getAttribute('name') == 'boardgame') {
        final v = r.getAttribute('value');
        if (v != null && v != 'Not Ranked') rank = int.tryParse(v);
      }
    }

    final cats = <String>[];
    final mechs = <String>[];
    final exps = <Expansion>[];

    for (final link in item.findElements('link')) {
      final type = link.getAttribute('type');
      final val = link.getAttribute('value') ?? '';
      final inbound = link.getAttribute('inbound') == 'true';

      if (type == 'boardgamecategory') cats.add(val);
      if (type == 'boardgamemechanic') mechs.add(val);
      if (type == 'boardgameexpansion' && inbound) {
        final eid = link.getAttribute('id') ?? '';
        if (eid.isNotEmpty) exps.add(Expansion(id: eid, name: val));
      }
    }

    return Game(
      id: id,
      name: primaryName,
      year: getValue('yearpublished'),
      minPlayers: int.tryParse(getValue('minplayers')) ?? 0,
      maxPlayers: int.tryParse(getValue('maxplayers')) ?? 0,
      playtime: getValue('playingtime'),
      minAge: getValue('minage'),
      weight: weight,
      rank: rank,
      rating: rating,
      imageUrl: item.findElements('image').firstOrNull?.innerText,
      categories: cats,
      mechanics: mechs,
      expansions: exps,
    );
  }

  // Live BGG data (token configured). Demo data only as fallback if token removed.

  Future<List<Game>> fetchUserCollection(String username) async {
    if (token == null || token!.isEmpty) {
      return [];
    }

    final url = _appendToken(
        '$_base/collection?username=$username&own=1&subtype=boardgame&excludessubtype=boardgameexpansion');
    final uri = Uri.parse(url);

    http.Response resp;
    try {
      resp = await http.get(uri, headers: _headers);
    } catch (_) {
      return [];
    }

    // Handle 202 processing
    if (resp.statusCode == 202) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        resp = await http.get(uri, headers: _headers);
      } catch (_) {
        return [];
      }
    }

    if (resp.statusCode != 200 || resp.body.isEmpty) {
      return [];
    }

    return _parseCollection(resp.body);
  }

  List<Game> _parseCollection(String body) {
    final document = XmlDocument.parse(body);
    final items = document.findAllElements('item');

    final results = <Game>[];
    for (final item in items) {
      final id = item.getAttribute('objectid') ?? '';
      if (id.isEmpty) continue;

      final nameEl = item.findElements('name').firstOrNull;
      final name = nameEl?.innerText ?? 'Unknown';

      final yearEl = item.findElements('yearpublished').firstOrNull;
      final year = yearEl?.innerText ?? '';

      final imageEl = item.findElements('image').firstOrNull;
      final imageUrl = imageEl?.innerText;

      final thumbEl = item.findElements('thumbnail').firstOrNull;
      final thumbnail = thumbEl?.innerText;

      // Basic stats if present in collection export
      double? rating;
      final stats = item.findElements('stats').firstOrNull;
      if (stats != null) {
        final ratingEl = stats.findElements('rating').firstOrNull;
        final avgEl = ratingEl?.findElements('average').firstOrNull;
        if (avgEl != null) {
          rating = double.tryParse(avgEl.getAttribute('value') ?? '');
        }
      }

      results.add(Game(
        id: id,
        name: name,
        year: year,
        imageUrl: imageUrl,
        // thumbnail can be used if we extend model, for now use image
      ));
    }
    return results;
  }
}
