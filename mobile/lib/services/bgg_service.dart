import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/game.dart';

class BggService {
  static const String _base = 'https://boardgamegeek.com/xmlapi2';
  final String? token;

  BggService({this.token});

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

  Future<List<Game>> searchGames(String query, {int limit = 10, int start = 0}) async {
    if (query.trim().length < 2) return [];

    // Only include start if >0. BGG search pagination is unreliable; omitting for initial searches helps.
    String url = '$_base/search?query=${Uri.encodeComponent(query)}&type=boardgame';
    if (start > 0) url += '&start=$start';
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
    // Always try the live BGG API first to get complete data (expansions, full stats, etc.)
    try {
      final uri = Uri.parse('$_base/thing?id=$id&stats=1');
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

  // No more hardcoded popular games. All data comes from live BGG searches.
}
