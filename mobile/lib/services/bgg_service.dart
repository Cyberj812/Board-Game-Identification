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

  Future<List<Game>> searchGames(String query, {int limit = 10}) async {
    if (query.trim().length < 2) return [];

    final uri = Uri.parse('$_base/search?query=${Uri.encodeComponent(query)}&type=boardgame');
    final resp = await http.get(uri, headers: _headers);

    if (resp.statusCode != 200) {
      // Fallback to popular if blocked
      return _popularGames.where((g) => g.name.toLowerCase().contains(query.toLowerCase())).toList();
    }

    final document = XmlDocument.parse(resp.body);
    final items = document.findAllElements('item');

    final results = <Game>[];
    for (final item in items.take(limit)) {
      final id = item.getAttribute('id') ?? '';
      final nameEl = item.findElements('name').firstWhere(
            (e) => e.getAttribute('type') == 'primary' || true,
            orElse: () => item.findElements('name').first,
          );
      final name = nameEl.getAttribute('value') ?? 'Unknown';
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
      // fall through to static on failure
    }

    // Fallback to static popular data
    return _popularGamesMap[id];
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
    final weightEl = stats?.findElements('averageweight').firstOrNull;
    if (weightEl != null) weight = double.tryParse(weightEl.getAttribute('value') ?? '');

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
      imageUrl: item.findElements('image').firstOrNull?.innerText,
      categories: cats,
      mechanics: mechs,
      expansions: exps,
    );
  }

  // Built-in popular games (works offline / when API is restricted)
  static final List<Game> _popularGames = [
    Game(
      id: '266192',
      name: 'Wingspan',
      year: '2019',
      minPlayers: 1,
      maxPlayers: 5,
      playtime: '40-70',
      weight: 2.4,
      rank: 38,
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
      digitalPlatforms: [
        DigitalPlatform(name: 'Tabletop Simulator', url: 'https://store.steampowered.com/app/286160/Tabletop_Simulator/'),
      ],
    ),
    Game(
      id: '13',
      name: 'Catan',
      year: '1995',
      minPlayers: 3,
      maxPlayers: 4,
      playtime: '60-120',
      weight: 2.3,
      rank: 400,
      digitalPlatforms: [
        DigitalPlatform(name: 'Tabletop Simulator', url: 'https://store.steampowered.com/app/286160/Tabletop_Simulator/'),
        DigitalPlatform(name: 'Catan Universe (Steam)', url: 'https://store.steampowered.com/app/544730/Catan_Universe/'),
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
    ),
    Game(
      id: '199792',
      name: 'Everdell',
      year: '2018',
      minPlayers: 1,
      maxPlayers: 4,
      playtime: '40-80',
      weight: 2.8,
      rank: 55,
      digitalPlatforms: [
        DigitalPlatform(name: 'Tabletop Simulator', url: 'https://store.steampowered.com/app/286160/Tabletop_Simulator/'),
      ],
    ),
  ];

  static final Map<String, Game> _popularGamesMap =
      {for (final g in _popularGames) g.id: g};

  List<Game> getPopularGames() => _popularGames;
}
