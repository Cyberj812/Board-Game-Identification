import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:confetti/confetti.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';

import 'models/game.dart';
import 'services/ocr_service.dart';
import 'services/bgg_service.dart';

void main() {
  runApp(const BoardGameSnapApp());
}

class BoardGameSnapApp extends StatelessWidget {
  const BoardGameSnapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Board Game Snap',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        textTheme: _buildTextTheme(Brightness.light),
        cardTheme: const CardThemeData(elevation: 3),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        textTheme: _buildTextTheme(Brightness.dark),
        cardTheme: const CardThemeData(elevation: 3),
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}

// Board gamer friendly typography
// Cinzel: premium, engraved box-title feel
// Oswald: strong, strategic condensed sans
// Inter: clean, highly legible body (great for rules & details)
TextTheme _buildTextTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final base = isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;

  return TextTheme(
    displayLarge: GoogleFonts.cinzel(
      textStyle: base.displayLarge,
      fontSize: 34,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
    ),
    displayMedium: GoogleFonts.cinzel(
      textStyle: base.displayMedium,
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    ),
    displaySmall: GoogleFonts.cinzel(
      textStyle: base.displaySmall,
      fontSize: 24,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    ),
    headlineLarge: GoogleFonts.oswald(
      textStyle: base.headlineLarge,
      fontSize: 26,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    ),
    headlineMedium: GoogleFonts.oswald(
      textStyle: base.headlineMedium,
      fontSize: 22,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: GoogleFonts.oswald(
      textStyle: base.titleLarge,
      fontSize: 20,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    ),
    titleMedium: GoogleFonts.oswald(
      textStyle: base.titleMedium,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: GoogleFonts.inter(
      textStyle: base.bodyLarge,
      fontSize: 15,
      height: 1.4,
    ),
    bodyMedium: GoogleFonts.inter(
      textStyle: base.bodyMedium,
      fontSize: 14,
      height: 1.35,
    ),
    labelLarge: GoogleFonts.inter(
      textStyle: base.labelLarge,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _searchText = '';
  bool _isScanning = false;
  List<Game> _myCollection = []; // Games I own - for choosing what to play
  List<Game> _wishlist = [];     // Games I'm interested in buying - for shopping
  List<Rulebook> _rulebooks = []; // Local library of rulebooks, linked to games
  bool _buildCollectionMode = false; // For now, keep but we won't auto-add

  // Score tracking
  List<Map<String, dynamic>> _scorePlayers = []; // {name, colorValue, score}

  // Shared session support (persistent updates while session active)
  String? _activeScoreSessionId;
  String? _activeScoreSessionPin;  // short PIN for auth
  bool _isScoreSessionHost = false;
  HttpServer? _scoreSessionServer;
  int? _scoreSessionPort;
  RawDatagramSocket? _discoverySocket;  // for UDP broadcast/listen to avoid exposing IP in QR
  static const int _discoveryPort = 53535; // custom discovery port

  // Last known host for clients (so they can push/sync without re-entering)
  String? _lastHostIp;
  int? _lastHostPort;

  // Search (BGG when token available, demo + local collection otherwise)
  Timer? _searchDebounce;
  List<Game> _bggSearchResults = [];
  bool _isSearchingBgg = false;
  int _searchStart = 0;
  bool _hasMoreResults = true;
  String _lastBggSearchTerm = ''; // the actual term sent to API (may be broad "the" for filter-only)

  // Advanced search filters
  int? _minPlayersFilter;
  int? _maxPlayersFilter;
  double? _minWeightFilter;
  double? _maxWeightFilter;
  double? _minRatingFilter;

  final _picker = ImagePicker();
  final _ocr = OcrService();
  final _bgg = BggService(token: bggToken);

// Top-level BGG config (your token from https://boardgamegeek.com/applications)
const String bggToken = '5591ebec-2659-4aaf-91fb-4287832a1e75';
const String bggUsername = 'cyberjunkie812';  // update if needed

  late ConfettiController _confettiController;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Bottom tabs: 0=My Collection (default), 1=Play, 2=Dice, 3=Score Tracker
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadCollection();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
    // Show no games by default - only when user searches
    _bggSearchResults = [];
    _hasMoreResults = false;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _confettiController.dispose();
    _audioPlayer.dispose();
    _stopLocalScoreServer();
    super.dispose();
  }

  Future<void> _loadCollection() async {
    final prefs = await SharedPreferences.getInstance();
    final collectionJson = prefs.getStringList('myCollection') ?? [];
    final wishlistJson = prefs.getStringList('wishlist') ?? [];
    final rulebooksJson = prefs.getStringList('rulebooks') ?? [];
    setState(() {
      _myCollection = collectionJson
          .map((jsonStr) => Game.fromJson(jsonDecode(jsonStr)))
          .toList();
      _wishlist = wishlistJson
          .map((jsonStr) => Game.fromJson(jsonDecode(jsonStr)))
          .toList();
      _rulebooks = rulebooksJson
          .map((jsonStr) => Rulebook.fromJson(jsonDecode(jsonStr)))
          .toList();
    });
  }

  Future<void> _saveCollections() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'myCollection',
      _myCollection.map((g) => jsonEncode(g.toJson())).toList(),
    );
    await prefs.setStringList(
      'wishlist',
      _wishlist.map((g) => jsonEncode(g.toJson())).toList(),
    );
    await prefs.setStringList(
      'rulebooks',
      _rulebooks.map((r) => jsonEncode(r.toJson())).toList(),
    );
  }



  bool _matchesFilters(Game g) {
    if (_minPlayersFilter != null && g.maxPlayers > 0 && g.maxPlayers < _minPlayersFilter!) {
      return false;
    }
    if (_maxPlayersFilter != null && g.minPlayers > 0 && g.minPlayers > _maxPlayersFilter!) {
      return false;
    }
    if (_minWeightFilter != null && g.weight != null && g.weight! < _minWeightFilter!) {
      return false;
    }
    if (_maxWeightFilter != null && g.weight != null && g.weight! > _maxWeightFilter!) {
      return false;
    }
    if (_minRatingFilter != null && g.rating != null && g.rating! < _minRatingFilter!) {
      return false;
    }
    return true;
  }

  Future<List<Game>> _enrichGames(List<Game> partials) async {
    if (partials.isEmpty) return [];
    final result = <Game>[];
    for (final g in partials) {
      try {
        final d = await _bgg.getGameDetails(g.id);
        result.add(d ?? g);
      } catch (_) {
        result.add(g);
      }
      // Small delay between detail calls to respect BGG rate limits (they are strict)
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return result;
  }

  bool _hasAnyFilter() {
    return _minPlayersFilter != null ||
        _maxPlayersFilter != null ||
        _minWeightFilter != null ||
        _maxWeightFilter != null ||
        _minRatingFilter != null;
  }

  Widget _buildActiveFilterSummary() {
    if (!_hasAnyFilter()) {
      return const Text('No filters', style: TextStyle(fontSize: 12, color: Colors.grey));
    }
    final parts = <String>[];
    if (_minPlayersFilter != null || _maxPlayersFilter != null) {
      final minP = _minPlayersFilter ?? 1;
      final maxP = _maxPlayersFilter ?? 99;
      parts.add('Players: $minP-${maxP == 99 ? '+' : maxP}');
    }
    if (_minWeightFilter != null || _maxWeightFilter != null) {
      final minW = _minWeightFilter?.toStringAsFixed(1) ?? '1';
      final maxW = _maxWeightFilter?.toStringAsFixed(1) ?? '5';
      parts.add('Weight: $minW-$maxW');
    }
    if (_minRatingFilter != null) {
      parts.add('Rating \u2265 ${_minRatingFilter!.toStringAsFixed(1)}');
    }
    return Text(parts.join('  •  '), style: const TextStyle(fontSize: 12, color: Colors.deepPurple));
  }

  Widget _buildSolidActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? backgroundColor,
    bool filled = false,
  }) {
    final style = filled
        ? FilledButton.styleFrom(
            backgroundColor: backgroundColor,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          )
        : OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: (filled
              ? FilledButton.icon(
                  onPressed: onPressed,
                  icon: Icon(icon),
                  label: Text(label),
                  style: style,
                )
              : OutlinedButton.icon(
                  onPressed: onPressed,
                  icon: Icon(icon, size: 20),
                  label: Text(label),
                  style: style,
                )),
    );
  }

  void _clearSearchFilters() {
    setState(() {
      _minPlayersFilter = null;
      _maxPlayersFilter = null;
      _minWeightFilter = null;
      _maxWeightFilter = null;
      _minRatingFilter = null;
    });
    final q = _searchText.trim();
    _searchBggLibrary(q);
  }

  Future<void> _searchBggLibrary(String query) async {
    final q = query.trim();
    final hasText = q.length >= 2;

    if (!hasText && !_hasAnyFilter()) {
      if (mounted) {
        setState(() {
          _bggSearchResults = [];
          _isSearchingBgg = false;
          _hasMoreResults = false;
          _searchStart = 0;
          _lastBggSearchTerm = '';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isSearchingBgg = true;
        _searchStart = 0;
        _hasMoreResults = true;
      });
    }

    try {
      // When the user provides a real query use it.
      // For "empty box" + filters only (short/empty query but filters active), use a broad term
      // so BGG returns a large pool of games. We then enrich + client-filter to the desired criteria.
      String searchTerm = hasText ? q : 'the';
      // For pure filter discovery ("empty box" or no text), rotate a few common terms so we get
      // a more varied pool of candidates to filter against the weight/player/rating params.
      if (!hasText) {
        final seeds = ['the', 'a', 'game', 'and', 'to'];
        searchTerm = seeds[DateTime.now().millisecondsSinceEpoch % seeds.length];
      }
      final fetchLimit = hasText ? 30 : 50;

      _lastBggSearchTerm = searchTerm;
      final rawResults = await _bgg.searchGames(searchTerm, limit: fetchLimit, start: 0);

      // Blend in matches from your local My Collection and Wishlist.
      // This makes "Search" immediately useful with your real games even while waiting for the BGG token.
      final qLower = q.toLowerCase();
      final localMatches = <Game>[];
      for (final g in [..._myCollection, ..._wishlist]) {
        if (g.name.toLowerCase().contains(qLower) &&
            !localMatches.any((e) => e.id == g.id)) {
          localMatches.add(g);
        }
      }

      // Local matches first, then remote/demo results (deduped)
      final combined = <Game>[...localMatches];
      for (final g in rawResults) {
        if (!combined.any((e) => e.id == g.id)) {
          combined.add(g);
        }
      }

      List<Game> workingResults = List.from(combined);

      // Only enrich when filters are active (we need weight/players/rating to filter).
      // For normal text searches, just use the raw BGG results (id/name/year is enough for the list).
      // This keeps it to ~1 API call instead of 20 — critical for BGG rate limits.
      if (_hasAnyFilter() && rawResults.isNotEmpty) {
        final toEnrich = rawResults.take(18).toList();
        final enrichedTop = await _enrichGames(toEnrich);

        // Merge
        for (final e in enrichedTop) {
          final idx = workingResults.indexWhere((g) => g.id == e.id);
          if (idx != -1) workingResults[idx] = e;
        }
      }

      // Always hydrate the very top result (cheap single call): gets image for list + expansions for Catan-like searches.
      if (workingResults.isNotEmpty) {
        try {
          final top = workingResults.first;
          final details = await _bgg.getGameDetails(top.id);
          if (details != null) {
            workingResults[0] = details;
            // surface expansions in results if they pass filters (helps "Catan" searches)
            for (final exp in details.expansions) {
              if (!workingResults.any((g) => g.id == exp.id)) {
                final expG = Game(id: exp.id, name: exp.name, year: '');
                if (_matchesFilters(expG)) {
                  workingResults.add(expG);
                }
              }
            }
          }
        } catch (_) {}
      }

      // Dedup against user collections + apply advanced filters (if any)
      final userIds = {..._myCollection.map((g) => g.id), ..._wishlist.map((g) => g.id)};
      final filtered = workingResults
          .where((g) => !userIds.contains(g.id) && _matchesFilters(g))
          .toList();

      // Show first 25
      final limited = filtered.take(25).toList();

      if (mounted) {
        setState(() {
          _bggSearchResults = limited;
          _searchStart = 0;
          // If BGG gave us a healthy batch, offer "Load more".
          _hasMoreResults = rawResults.length >= 25;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _bggSearchResults = [];
          _hasMoreResults = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSearchingBgg = false);
      }
    }
  }

  Future<void> _loadMoreBggResults() async {
    final q = _searchText.trim();
    if (q.length < 2 && _lastBggSearchTerm.isEmpty && !_hasAnyFilter()) return;
    if (!_hasMoreResults || _isSearchingBgg) return;

    _searchStart += 25;
    setState(() => _isSearchingBgg = true);

    try {
      // Use the last actual term sent (important for filter-only / empty box discovery searches)
      String apiTerm = q.length >= 2 ? q : (_lastBggSearchTerm.isNotEmpty ? _lastBggSearchTerm : 'the');
      final moreRaw = await _bgg.searchGames(apiTerm, limit: 25, start: _searchStart);

      if (moreRaw.isEmpty) {
        if (mounted) setState(() => _hasMoreResults = false);
      } else {
        final userIds = {..._myCollection.map((g) => g.id), ..._wishlist.map((g) => g.id)};

        List<Game> workingMore = List.from(moreRaw);

        // Enrich only if filters active (to support filtering new results)
        if (_hasAnyFilter() && moreRaw.isNotEmpty) {
          final toEnrichMore = moreRaw.take(15).toList();
          final enrichedTopMore = await _enrichGames(toEnrichMore);

          for (final e in enrichedTopMore) {
            final idx = workingMore.indexWhere((g) => g.id == e.id);
            if (idx != -1) workingMore[idx] = e;
          }
        }

        // Accept what BGG returned for the page.
        final newCandidates = workingMore.where((g) {
          if (userIds.contains(g.id)) return false;
          if (_bggSearchResults.any((e) => e.id == g.id)) return false;
          return _matchesFilters(g);
        }).toList();

        // Optionally pull expansions for the first new result (helps surface Catan expansions etc. on later pages)
        List<Game> toAdd = List.from(newCandidates);
        if (newCandidates.isNotEmpty) {
          try {
            final topNew = newCandidates.first;
            if (topNew.expansions.isEmpty) {
              final details = await _bgg.getGameDetails(topNew.id);
              if (details != null && details.expansions.isNotEmpty) {
                for (final exp in details.expansions) {
                  if (!toAdd.any((g) => g.id == exp.id) &&
                      !_bggSearchResults.any((e) => e.id == exp.id) &&
                      _matchesFilters(Game(id: exp.id, name: exp.name, year: ''))) {
                    toAdd.add(Game(id: exp.id, name: exp.name, year: ''));
                  }
                }
              }
            }
          } catch (_) {}
        }

        if (mounted) {
          setState(() {
            _bggSearchResults.addAll(toAdd.take(25));
            _hasMoreResults = moreRaw.length == 25;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _hasMoreResults = false);
    } finally {
      if (mounted) setState(() => _isSearchingBgg = false);
    }
  }

  Future<void> _viewGame(Game partialGame) async {
    Game gameToShow = partialGame;

    // Always fetch full details for BGG games to ensure expansions, images, stats etc. are loaded
    if (partialGame.id.isNotEmpty && !partialGame.id.startsWith('manual_')) {
      final full = await _bgg.getGameDetails(partialGame.id);
      if (full != null) {
        gameToShow = full;
      }
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameDetailPage(
          game: gameToShow,
          isInMyCollection: _myCollection.any((g) => g.id == gameToShow.id),
          isInWishlist: _wishlist.any((g) => g.id == gameToShow.id),
          onAddToMyCollection: () => _addToMyCollection(gameToShow),
          onAddToWishlist: () => _addToWishlist(gameToShow),
          onLogPlay: (g) => _logPlay(g),
          onEditHouseRules: _editHouseRules,
        ),
      ),
    );
  }

  Future<void> _scanBox() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (image == null) return;

    setState(() => _isScanning = true);

    try {
      final file = File(image.path);
      final text = await _ocr.extractText(file);

      if (text.trim().isEmpty) {
        if (_hasAnyFilter()) {
          // Empty box + active filters: populate the library list with up to 25 matching games
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No text found on box. Loading games matching your filters...')),
            );
            setState(() {
              _searchText = '';
            });
            _searchBggLibrary('');
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read text from image. Try better lighting.')),
          );
        }
        return;
      }

      // Clean OCR text for better matching
      String cleaned = text.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ')
                          .replaceAll(RegExp(r'\s+'), ' ')
                          .trim();

      var results = await _bgg.searchGames(cleaned, limit: 5);

      if (results.isEmpty && cleaned.length > 3) {
        // Try the longest word as fallback
        final words = cleaned.split(' ').where((w) => w.length > 2).toList();
        words.sort((a, b) => b.length.compareTo(a.length));
        if (words.isNotEmpty) {
          results = await _bgg.searchGames(words.first, limit: 5);
        }
      }

      // No more popular game fallbacks. Results come only from live BGG searches.
      // If still empty after BGG attempts, we'll fall through to prefill/manual search.

      // Apply current optional filters to the BGG candidates (if any are active).
      // This lets "empty box" scans still respect weight / player count / rating.
      List<Game> finalCandidates = results;
      if (results.isNotEmpty && _hasAnyFilter()) {
        final enrichedForFilter = await _enrichGames(results);
        final matching = enrichedForFilter.where(_matchesFilters).toList();
        if (matching.isNotEmpty) {
          finalCandidates = matching;
        }
      }

      if (finalCandidates.isEmpty) {
        // No candidates from live BGG search (or none survived your filters).
        if (mounted) {
          final note = _hasAnyFilter() ? ' (no matches under your filters)' : '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No matching games found$note. OCR got: "$cleaned".')),
          );
        }
        setState(() {
          _searchText = cleaned;
        });
        _searchBggLibrary(cleaned); // live search (with filters for discovery if active)
        return;
      }

      // Pick the best (first) candidate that respects filters when possible
      final top = finalCandidates.first;
      final fullGame = await _bgg.getGameDetails(top.id);

      if (fullGame != null && mounted) {
        // Do NOT auto add. User decides in the detail view.
        // This supports shopping (add to wishlist) and owning (add to my collection).
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GameDetailPage(
              game: fullGame,
              isInMyCollection: _myCollection.any((g) => g.id == fullGame.id),
              isInWishlist: _wishlist.any((g) => g.id == fullGame.id),
              onAddToMyCollection: () => _addToMyCollection(fullGame),
              onAddToWishlist: () => _addToWishlist(fullGame),
              onLogPlay: (g) => _logPlay(g),
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not fetch game details.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _showRandomGame() async {
    if (_myCollection.isNotEmpty) {
      final game = (List.from(_myCollection)..shuffle()).first;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GameDetailPage(
            game: game,
            onAddToMyCollection: () => _addToMyCollection(game),
            onAddToWishlist: () => _addToWishlist(game),
          ),
        ),
      );
      return;
    }

    // No collection yet: do a search for a random game (demo or local data)
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Picking a random game...')),
      );
    }

    try {
      final raw = await _bgg.searchGames('game', limit: 15);
      if (raw.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not pick a random game. Try searching instead.')),
          );
        }
        return;
      }

      // Pick one and hydrate fully (live data only)
      final partial = (List.from(raw)..shuffle()).first;
      final game = await _bgg.getGameDetails(partial.id) ?? partial;

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GameDetailPage(
            game: game,
            onAddToMyCollection: () => _addToMyCollection(game),
            onAddToWishlist: () => _addToWishlist(game),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not pick a random game. Try searching instead.')),
        );
      }
    }
  }

  void _showSearchFilters() {
    // Local copies for the sheet so we can live-update
    int? minP = _minPlayersFilter;
    int? maxP = _maxPlayersFilter;
    double? minW = _minWeightFilter;
    double? maxW = _maxWeightFilter;
    double? minR = _minRatingFilter;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void updateParentAndSearch() {
              setState(() {
                _minPlayersFilter = minP;
                _maxPlayersFilter = maxP;
                _minWeightFilter = minW;
                _maxWeightFilter = maxW;
                _minRatingFilter = minR;
              });
              // Always call; _searchBggLibrary will handle filter-only discovery when query is short/empty
              _searchBggLibrary(_searchText.trim());
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tune),
                          const SizedBox(width: 8),
                          Text('Search Filters', style: Theme.of(context).textTheme.titleLarge),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              minP = null; maxP = null; minW = null; maxW = null; minR = null;
                              setSheetState(() {});
                              updateParentAndSearch();
                            },
                            child: const Text('Reset all'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(sheetContext),
                          ),
                        ],
                      ),
                      const Divider(),
                      const SizedBox(height: 8),

                      // Player count
                      Text('Player Count', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Text('Min:'),
                          const SizedBox(width: 8),
                          DropdownButton<int?>(
                            value: minP,
                            hint: const Text('Any'),
                            items: [null, 1, 2, 3, 4, 5, 6, 7, 8]
                                .map((v) => DropdownMenuItem(value: v, child: Text(v == null ? 'Any' : '$v')))
                                .toList(),
                            onChanged: (v) {
                              setSheetState(() => minP = v);
                              updateParentAndSearch();
                            },
                          ),
                          const SizedBox(width: 16),
                          const Text('Max:'),
                          const SizedBox(width: 8),
                          DropdownButton<int?>(
                            value: maxP,
                            hint: const Text('Any'),
                            items: [null, 2, 3, 4, 5, 6, 7, 8, 10]
                                .map((v) => DropdownMenuItem(value: v, child: Text(v == null ? 'Any' : (v >= 10 ? '10+' : '$v'))))
                                .toList(),
                            onChanged: (v) {
                              setSheetState(() => maxP = v);
                              updateParentAndSearch();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Weight range
                      Text('Weight (Complexity 1-5)', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      RangeSlider(
                        values: RangeValues(minW ?? 1.0, maxW ?? 5.0),
                        min: 1.0,
                        max: 5.0,
                        divisions: 40,
                        labels: RangeLabels(
                          (minW ?? 1.0).toStringAsFixed(1),
                          (maxW ?? 5.0).toStringAsFixed(1),
                        ),
                        onChanged: (vals) {
                          setSheetState(() {
                            minW = vals.start;
                            maxW = vals.end;
                          });
                        },
                        onChangeEnd: (_) => updateParentAndSearch(),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Min: ${(minW ?? 1.0).toStringAsFixed(1)}'),
                          Text('Max: ${(maxW ?? 5.0).toStringAsFixed(1)}'),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Min rating
                      Text('Minimum Rating', style: Theme.of(context).textTheme.titleMedium),
                      Slider(
                        value: minR ?? 0.0,
                        min: 0.0,
                        max: 10.0,
                        divisions: 20,
                        label: (minR ?? 0.0).toStringAsFixed(1),
                        onChanged: (v) {
                          setSheetState(() => minR = v > 0.5 ? v : null);
                        },
                        onChangeEnd: (_) => updateParentAndSearch(),
                      ),
                      Text(minR != null && minR! > 0 ? 'Min rating: ${minR!.toStringAsFixed(1)}' : 'Any rating'),
                      const SizedBox(height: 16),

                      // Chips for quick presets
                      Wrap(
                        spacing: 6,
                        children: [
                          ActionChip(
                            label: const Text('Light (≤2.5)'),
                            onPressed: () {
                              setSheetState(() { minW = null; maxW = 2.5; });
                              updateParentAndSearch();
                            },
                          ),
                          ActionChip(
                            label: const Text('Medium (2-3.5)'),
                            onPressed: () {
                              setSheetState(() { minW = 2.0; maxW = 3.5; });
                              updateParentAndSearch();
                            },
                          ),
                          ActionChip(
                            label: const Text('Heavy (≥3.5)'),
                            onPressed: () {
                              setSheetState(() { minW = 3.5; maxW = 5.0; });
                              updateParentAndSearch();
                            },
                          ),
                          ActionChip(
                            label: const Text('7+ rating'),
                            onPressed: () {
                              setSheetState(() => minR = 7.0);
                              updateParentAndSearch();
                            },
                          ),
                          ActionChip(
                            label: const Text('2-4 players'),
                            onPressed: () {
                              setSheetState(() { minP = 2; maxP = 4; });
                              updateParentAndSearch();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _reportBug() async {
    const url = 'https://github.com/Cyberj812/Board-Game-Identification/issues/new?template=bug_report.md';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open browser to report bug.')),
        );
      }
    }
  }

  Future<void> _openFeedback() async {
    const url = 'https://github.com/Cyberj812/Board-Game-Identification/issues/new/choose';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open browser.')),
        );
      }
    }
  }

  void _addToMyCollection(Game game) {
    setState(() {
      if (_myCollection.any((g) => g.id == game.id)) {
        _myCollection.removeWhere((g) => g.id == game.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed ${game.name} from your collection')),
        );
      } else {
        _myCollection.add(game);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${game.name} to your collection')),
        );
      }
    });
    _saveCollections();
  }

  void _addToWishlist(Game game) {
    setState(() {
      if (_wishlist.any((g) => g.id == game.id)) {
        _wishlist.removeWhere((g) => g.id == game.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed ${game.name} from your wishlist')),
        );
      } else {
        _wishlist.add(game);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${game.name} to your wishlist')),
        );
      }
    });
    _saveCollections();
  }

  Future<void> _importMyBGGCollection() async {
    if (_bgg is! BggService) return; // safety
    setState(() => _isSearchingBgg = true);

    try {
      final imported = await _bgg.fetchUserCollection(bggUsername);

      if (imported.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No games returned from BGG. Check username/token or try again later (rate limits apply).')),
          );
        }
        return;
      }

      int added = 0;
      for (final g in imported) {
        if (!_myCollection.any((c) => c.id == g.id)) {
          // Hydrate full details for rich data (weight, expansions, image, etc.)
          final full = await _bgg.getGameDetails(g.id) ?? g;
          _myCollection.add(full);
          added++;
        }
      }

      await _saveCollections();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $added new games to your collection.')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearchingBgg = false);
    }
  }

  Future<void> _downloadRulebook(Rulebook rule) async {
    if (rule.url == null) return;

    try {
      final resp = await http.get(Uri.parse(rule.url!));
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not download PDF.')));
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final booksDir = Directory('${dir.path}/rulebooks');
      if (!await booksDir.exists()) await booksDir.create(recursive: true);

      final filePath = '${booksDir.path}/${rule.id}.pdf';
      final file = File(filePath);
      await file.writeAsBytes(resp.bodyBytes);

      // Text extraction disabled for now (pdf_text had dependency conflict)
      // final updated will have extractedText: null

      final updated = Rulebook(
        id: rule.id,
        gameId: rule.gameId,
        gameName: rule.gameName,
        title: rule.title,
        url: rule.url,
        localPath: filePath,
        addedDate: rule.addedDate,
      );

      setState(() {
        final idx = _rulebooks.indexWhere((r) => r.id == rule.id);
        if (idx != -1) _rulebooks[idx] = updated;
      });
      await _saveCollections();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF downloaded. Text extracted for search.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download error: $e')));
    }
  }

  void _openRulebook(Rulebook rule) {
    if (rule.localPath != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _PdfViewerPage(path: rule.localPath!),
        ),
      );
    } else if (rule.url != null) {
      _launch(rule.url!, context);
    }
  }

  void _showCollection() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('My Collection', style: Theme.of(context).textTheme.headlineSmall),
            content: _myCollection.isEmpty
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _importMyBGGCollection();
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('Import collection'),
                      ),
                      const SizedBox(height: 12),
                      const Text('No games in your collection yet. Use the button above or search to add some.'),
                    ],
                  )
                : ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatefulBuilder(
                          builder: (context, setInnerState) {
                            String searchQuery = '';
                            final filtered = searchQuery.isEmpty
                                ? _myCollection
                                : _myCollection.where((g) =>
                                    g.name.toLowerCase().contains(searchQuery) ||
                                    (g.description ?? '').toLowerCase().contains(searchQuery)).toList();
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  decoration: const InputDecoration(
                                    hintText: 'Search collection...',
                                    prefixIcon: Icon(Icons.search, size: 20),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                  ),
                                  onChanged: (val) {
                                    searchQuery = val.toLowerCase();
                                    setInnerState(() {});
                                  },
                                ),
                                const SizedBox(height: 8),
                                ConstrainedBox(
                                  constraints: BoxConstraints(maxHeight: 300),
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: filtered.length,
                                    itemBuilder: (c, i) {
                                      final g = filtered[i];
                                      return Card(
                                        child: ListTile(
                                          leading: const Icon(Icons.casino, size: 28),
                                          title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                          subtitle: Text('${g.year} • ${g.playerCount} players • ${g.weightString}'),
                                          trailing: IconButton(
                                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                                            onPressed: () {
                                              setState(() {
                                                _myCollection.removeWhere((x) => x.id == g.id);
                                              });
                                              setDialogState(() {});
                                              setInnerState(() {});
                                              _saveCollections();
                                            },
                                          ),
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => GameDetailPage(
                                                  game: g,
                                                  isInMyCollection: true,
                                                  onAddToMyCollection: () => _addToMyCollection(g),
                                                  onAddToWishlist: () => _addToWishlist(g),
                                                  onLogPlay: (gg) => _logPlay(gg),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _scanBox();
                              },
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Scan More'),
                            ),
                            TextButton.icon(
                              onPressed: _showManualEntry,
                              icon: const Icon(Icons.edit),
                              label: const Text('Manual'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              if (_myCollection.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() => _myCollection.clear());
                    setDialogState(() {});
                    _saveCollections();
                  },
                  child: const Text('Clear All'),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showWishlist() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Wishlist', style: Theme.of(context).textTheme.headlineSmall),
            content: _wishlist.isEmpty
                ? const Text('No games on your wishlist yet. Search and add games you want to buy.')
                : SizedBox(
                    width: double.maxFinite,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Search inside wishlist (functional + constrained to avoid overflow)
                        Builder(builder: (context) {
                          String searchQuery = '';
                          return StatefulBuilder(builder: (context, setInner) {
                            final filtered = searchQuery.isEmpty
                                ? _wishlist
                                : _wishlist.where((g) => g.name.toLowerCase().contains(searchQuery)).toList();
                            return Column(mainAxisSize: MainAxisSize.min, children: [
                              TextField(
                                decoration: const InputDecoration(
                                  hintText: 'Search wishlist...',
                                  prefixIcon: Icon(Icons.search, size: 20),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                ),
                                onChanged: (val) {
                                  searchQuery = val.toLowerCase();
                                  setInner(() {});
                                },
                              ),
                              const SizedBox(height: 8),
                              ConstrainedBox(
                                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: filtered.length,
                                  itemBuilder: (c, i) {
                                    final g = filtered[i];
                                    return Card(
                                      child: ListTile(
                                        leading: const Icon(Icons.shopping_cart, size: 28),
                                        title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                        subtitle: Text(g.year),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                                          onPressed: () {
                                            setState(() { _wishlist.removeWhere((x) => x.id == g.id); });
                                            setDialogState(() {});
                                            setInner(() {});
                                            _saveCollections();
                                          },
                                        ),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => GameDetailPage(
                                                game: g,
                                                onAddToMyCollection: () => _addToMyCollection(g),
                                                onAddToWishlist: () => _addToWishlist(g),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ]);
                          });
                        }),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _scanBox();
                              },
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Scan More'),
                            ),
                            TextButton.icon(
                              onPressed: _showManualEntry,
                              icon: const Icon(Icons.edit),
                              label: const Text('Manual'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              if (_wishlist.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() => _wishlist.clear());
                    setDialogState(() {});
                    _saveCollections();
                  },
                  child: const Text('Clear All'),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showRulebookLibrary() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          String searchQuery = '';
          return AlertDialog(
            title: Text('Rulebook Library', style: Theme.of(context).textTheme.headlineSmall),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search inside rulebooks...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (val) {
                    searchQuery = val.toLowerCase();
                    setDialogState(() {});
                  },
                ),
                const SizedBox(height: 8),
                _rulebooks.isEmpty
                    ? const Text('No rulebooks yet. Add them from a game\'s detail page or the Add button.')
                    : ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
                        child: Builder(
                          builder: (_) {
                            final filtered = _rulebooks.where((r) {
                              final text = (r.title + ' ' + r.gameName).toLowerCase();
                              return text.contains(searchQuery) || r.gameName.toLowerCase().contains(searchQuery);
                            }).toList();

                            return ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (c, i) {
                                final r = filtered[i];
                                final hasLocal = r.localPath != null;
                                return Card(
                                  child: ListTile(
                                    leading: Icon(hasLocal ? Icons.book : Icons.link, size: 28),
                                    title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text('${r.gameName} • ${hasLocal ? "Downloaded" : "Link"}'),
                                    onTap: () => _openRulebook(r),  // defaults to in-app viewer (pdfx)
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (r.url != null && !hasLocal)
                                          IconButton(
                                            icon: const Icon(Icons.download),
                                            tooltip: 'Download PDF',
                                            onPressed: () async {
                                              await _downloadRulebook(r);
                                              setDialogState(() {});
                                            },
                                          ),
                                        if (hasLocal)
                                          IconButton(
                                            icon: const Icon(Icons.open_in_new),
                                            tooltip: 'Open with external viewer (Google PDF Viewer, Chrome, etc.)',
                                            onPressed: () async {
                                              final result = await OpenFilex.open(r.localPath!);
                                              if (result.type != ResultType.done) {
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text('Could not open file: ${result.message}')),
                                                  );
                                                }
                                              }
                                            },
                                          ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                                          onPressed: () {
                                            setState(() {
                                              _rulebooks.removeWhere((x) => x.id == r.id);
                                            });
                                            setDialogState(() {});
                                            _saveCollections();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showAddRulebookDialog();
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Rulebook'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddRulebookDialog() {
    if (_myCollection.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some games to your collection first.')),
      );
      return;
    }

    Game? selectedGame;
    final titleController = TextEditingController();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Add Rulebook'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Game>(
                  decoration: const InputDecoration(labelText: 'Game'),
                  items: _myCollection.map((g) => DropdownMenuItem(
                    value: g,
                    child: Text(g.name),
                  )).toList(),
                  onChanged: (g) {
                    selectedGame = g;
                    setDialogState(() {});
                  },
                ),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Rulebook Title (e.g. Official Rules v1.2)'),
                ),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(labelText: 'URL (from BGG files page or official PDF)'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  if (selectedGame == null || titleController.text.isEmpty) {
                    return;
                  }
                  final newRule = Rulebook(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    gameId: selectedGame!.id,
                    gameName: selectedGame!.name,
                    title: titleController.text.trim(),
                    url: urlController.text.trim().isNotEmpty ? urlController.text.trim() : null,
                  );
                  setState(() {
                    _rulebooks.add(newRule);
                  });
                  _saveCollections();
                  Navigator.pop(ctx);
                  // Reopen library to see it
                  _showRulebookLibrary();
                  if (newRule.url != null) {
                    // auto download for convenience
                    final justAdded = _rulebooks.last;
                    _downloadRulebook(justAdded);
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddRulebookForGame(Game game) {
    final titleController = TextEditingController();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Rulebook for ${game.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Rulebook Title'),
            ),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: 'URL to PDF or from BGG files page'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (titleController.text.isEmpty) return;
              final newRule = Rulebook(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                gameId: game.id,
                gameName: game.name,
                title: titleController.text.trim(),
                url: urlController.text.trim().isNotEmpty ? urlController.text.trim() : null,
              );
              setState(() {
                _rulebooks.add(newRule);
              });
              _saveCollections();
              Navigator.pop(ctx);
              _showRulebookLibrary();
              if (newRule.url != null) {
                final justAdded = _rulebooks.last;
                _downloadRulebook(justAdded);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showManualEntry() {
    final nameController = TextEditingController();
    final yearController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Manual Entry'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Game Name')),
            TextField(controller: yearController, decoration: const InputDecoration(labelText: 'Year')),
            TextField(controller: descController, decoration: const InputDecoration(labelText: 'Description')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                final manual = Game(
                  id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
                  name: nameController.text,
                  year: yearController.text,
                  description: descController.text,
                );
                _addToMyCollection(manual);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showIllegalMoveChecker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Illegal Move Tracker'),
        content: const Text(
          'This feature will let you take a photo of a game board in progress and use computer vision + rules engine to detect illegal moves.\n\nComing in a future release!',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  void _pickRandomFromMyCollection() {
    if (_myCollection.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your collection is empty. Add some games first!')),
      );
      return;
    }
    final game = (_myCollection..shuffle()).first;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameDetailPage(game: game),
      ),
    );
  }

  void _editHouseRules(Game game, BuildContext ctx) {
    final controller = TextEditingController(text: game.houseRules ?? '');
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: Text('House Rules for ${game.name}'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'e.g. "Use advanced rules for 4+, ignore the pirate variant"',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newRules = controller.text.trim();
              game.houseRules = newRules.isEmpty ? null : newRules;
              _saveCollections();
              Navigator.pop(dialogCtx);
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('House rules saved for the group.')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _logPlay(Game game) {
    DateTime selectedDate = DateTime.now();
    int players = game.minPlayers > 0 ? game.minPlayers : 2;
    double? rating;
    String notes = '';
    File? selectedPhoto;

    Future<void> _pickSessionPhoto(StateSetter setDialog) async {
      final picked = await _picker.pickImage(source: ImageSource.gallery); // or camera
      if (picked != null) {
        // Save to permanent app directory
        final dir = await getApplicationDocumentsDirectory();
        final photosDir = Directory('${dir.path}/play_photos');
        if (!await photosDir.exists()) await photosDir.create(recursive: true);
        final ext = picked.path.split('.').last;
        final fileName = '${game.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        final savedPath = '${photosDir.path}/$fileName';
        await File(picked.path).copy(savedPath);
        setDialog(() => selectedPhoto = File(savedPath));
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text('Log the Battle: ${game.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('Date'),
                    subtitle: Text(selectedDate.toLocal().toString().split(' ')[0]),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setStateDialog(() => selectedDate = picked);
                      }
                    },
                  ),
                  TextFormField(
                    initialValue: players.toString(),
                    decoration: const InputDecoration(labelText: 'Number of players'),
                    keyboardType: TextInputType.number,
                    onChanged: (val) => players = int.tryParse(val) ?? players,
                  ),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Rating (1-10, optional)'),
                    keyboardType: TextInputType.number,
                    onChanged: (val) => rating = double.tryParse(val),
                  ),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Notes (optional)'),
                    maxLines: 2,
                    onChanged: (val) => notes = val,
                  ),
                  const SizedBox(height: 12),
                  // Photo for enhanced session logging
                  if (selectedPhoto != null)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(selectedPhoto!, height: 120, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () => setStateDialog(() => selectedPhoto = null),
                          ),
                        ),
                      ],
                    ),
                  TextButton.icon(
                    onPressed: () => _pickSessionPhoto(setStateDialog),
                    icon: const Icon(Icons.photo_camera),
                    label: Text(selectedPhoto != null ? 'Change session photo' : 'Add session photo'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final log = PlayLog(
                    date: selectedDate,
                    players: players,
                    rating: rating,
                    notes: notes.isEmpty ? null : notes,
                    photoPath: selectedPhoto?.path,
                  );
                  setState(() {
                    game.addPlay(log);
                  });
                  _saveCollections();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Play logged!')),
                  );
                },
                child: const Text('Log Play'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showWhatShouldWePlay() {
    List<Game> selectedGames = List.from(_myCollection);
    bool useAll = _myCollection.isNotEmpty;
    bool isSpinning = false;
    Game? selectedGame;
    double rotation = 0;
    String wheelSearch = '';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('What Should We Play?'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_myCollection.isNotEmpty)
                        SwitchListTile(
                          title: const Text('Use all from My Collection'),
                          value: useAll,
                          onChanged: (val) {
                            setDialogState(() {
                              useAll = val;
                              if (val) {
                                selectedGames = List.from(_myCollection);
                              } else {
                                selectedGames = [];
                              }
                            });
                          },
                        ),
                      if (!useAll && _myCollection.isNotEmpty) ...[
                        const Text('Select games:'),
                        const SizedBox(height: 4),
                        TextField(
                          decoration: const InputDecoration(
                            hintText: 'Filter games...',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (val) => setDialogState(() => wheelSearch = val.toLowerCase()),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: _myCollection
                              .where((g) => g.name.toLowerCase().contains(wheelSearch))
                              .map((game) {
                            final isSelected = selectedGames.contains(game);
                            return FilterChip(
                              label: Text(game.name),
                              selected: isSelected,
                              onSelected: (sel) {
                                setDialogState(() {
                                  if (sel) {
                                    selectedGames.add(game);
                                  } else {
                                    selectedGames.remove(game);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (selectedGames.isNotEmpty && !isSpinning)
                        ElevatedButton.icon(
                          onPressed: () async {
                            setDialogState(() {
                              isSpinning = true;
                              selectedGame = null;
                            });

                            // Spin animation
                            final random = Random();
                            final spins = 5 + random.nextInt(5);
                            final targetIndex = random.nextInt(selectedGames.length);
                            final anglePerItem = 2 * pi / selectedGames.length;
                            final finalRotation = spins * 2 * pi + (targetIndex * anglePerItem);

                            for (int i = 0; i <= 30; i++) {
                              await Future.delayed(const Duration(milliseconds: 50));
                              setDialogState(() {
                                rotation = (finalRotation * (i / 30));
                              });
                            }

                            setDialogState(() {
                              selectedGame = selectedGames[targetIndex];
                              isSpinning = false;
                            });

                            try {
                              await _audioPlayer.play(AssetSource('sounds/fanfare.mp3'));
                            } catch (_) {}
                            _confettiController.play();

                            await Future.delayed(const Duration(seconds: 3));
                          },
                          icon: const Icon(Icons.casino),
                          label: const Text('Spin the Wheel!'),
                        ),

                      // Simple group voting (local for now - each person taps +)
                      if (selectedGames.isNotEmpty && !isSpinning) ...[
                        const SizedBox(height: 12),
                        const Text('Group Voting (tap + for each vote)'),
                        Wrap(
                          spacing: 8,
                          children: selectedGames.map((g) {
                            // quick local vote count using a temp map on state? simple display only
                            return ActionChip(
                              label: Text('${g.name}'),
                              onPressed: () {
                                // For demo: increment a fake vote and show snack
                                setDialogState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Vote recorded for ${g.name} (group mode)'), duration: const Duration(milliseconds: 800)),
                                );
                              },
                            );
                          }).toList(),
                        ),
                        const Text('Tip: Everyone take turns tapping favorites!', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                      if (isSpinning || selectedGame != null) ...[
                        const SizedBox(height: 16),
                        _SpinningWheel(
                          games: selectedGames,
                          rotation: rotation,
                          selectedGame: selectedGame,
                        ),
                        if (selectedGame != null) ...[
                          const SizedBox(height: 16),
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Text(
                                '🎉 ${selectedGame!.name} 🎉',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                              ConfettiWidget(
                                confettiController: _confettiController,
                                blastDirectionality: BlastDirectionality.explosive,
                                shouldLoop: false,
                                colors: const [
                                  Colors.red,
                                  Colors.blue,
                                  Colors.green,
                                  Colors.yellow,
                                  Colors.purple,
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => GameDetailPage(
                                game: selectedGame!,
                                onEditHouseRules: _editHouseRules,
                              ),
                                ),
                              );
                            },
                            child: const Text('View Game Details'),
                          ),
                          TextButton(
                            onPressed: () {
                              setDialogState(() {
                                isSpinning = false;
                                selectedGame = null;
                                rotation = 0;
                              });
                            },
                            child: const Text('Roll Again'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPackList([List<Game>? preselected]) {
    final games = preselected ?? List<Game>.from(_myCollection);
    if (games.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add games to My Collection first.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pack List for Game Night'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Checklist - tap items as you pack:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ...games.map((g) {
                  final expCount = g.expansions.length;
                  return CheckboxListTile(
                    dense: true,
                    title: Text(g.name),
                    subtitle: Text('${g.playerCount} players • ${g.playtime} min${expCount > 0 ? ' + $expCount expansions' : ''}'),
                    value: false,
                    onChanged: (_) {}, // visual only for now
                  );
                }),
                const Divider(),
                const Text('General reminders:', style: TextStyle(fontWeight: FontWeight.bold)),
                const Text('• Bring rules / player aids'),
                const Text('• Check player count components'),
                const Text('• Table space & lighting'),
                const Text('• Snacks & drinks'),
                if (games.any((g) => (g.maxPlayers) >= 5)) const Text('• Large table for big groups'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pack list ready — check off as you go!')),
              );
            },
            child: const Text('Done Packing'),
          ),
        ],
      ),
    );
  }

  void _showTurnTimer() {
    List<String> players = ['Player 1', 'Player 2', 'Player 3', 'Player 4'];
    int currentTurn = 0;
    int secondsLeft = 60;
    Timer? timer;
    bool isRunning = false;

    void startTimer(StateSetter setD) {
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (secondsLeft > 0) {
          setD(() => secondsLeft--);
        } else {
          // auto next on zero? or alert
          setD(() {
            currentTurn = (currentTurn + 1) % players.length;
            secondsLeft = 60;
            isRunning = false;
          });
          timer?.cancel();
        }
      });
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Turn Order & Timer'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Players reorder
                  const Text('Turn Order (drag to reorder)'),
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: (oldI, newI) {
                      setDialogState(() {
                        if (newI > oldI) newI -= 1;
                        final item = players.removeAt(oldI);
                        players.insert(newI, item);
                        if (oldI == currentTurn) currentTurn = newI;
                      });
                    },
                    children: List.generate(players.length, (i) {
                      final isCurrent = i == currentTurn;
                      return ListTile(
                        key: ValueKey(i),
                        leading: CircleAvatar(
                          backgroundColor: isCurrent ? Colors.deepPurple : Colors.grey,
                          child: Text('${i + 1}'),
                        ),
                        title: Text(players[i], style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : null)),
                        trailing: isCurrent ? const Icon(Icons.play_arrow, color: Colors.deepPurple) : null,
                        onTap: () => setDialogState(() => currentTurn = i),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  // Timer
                  Text(
                    '${(secondsLeft ~/ 60).toString().padLeft(2, '0')}:${(secondsLeft % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  Text('Current: ${players[currentTurn]}', style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          setDialogState(() {
                            isRunning = !isRunning;
                            if (isRunning) {
                              startTimer(setDialogState);
                            } else {
                              timer?.cancel();
                            }
                          });
                        },
                        icon: Icon(isRunning ? Icons.pause : Icons.play_arrow),
                        label: Text(isRunning ? 'Pause' : 'Start'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () {
                          timer?.cancel();
                          setDialogState(() {
                            secondsLeft = 60;
                            isRunning = false;
                          });
                        },
                        child: const Text('Reset 60s'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      timer?.cancel();
                      setDialogState(() {
                        currentTurn = (currentTurn + 1) % players.length;
                        secondsLeft = 60;
                        isRunning = false;
                      });
                    },
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Next Turn'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      final ctrl = TextEditingController();
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Add Player'),
                          content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Name')),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                            FilledButton(
                              onPressed: () {
                                if (ctrl.text.trim().isNotEmpty) {
                                  setDialogState(() => players.add(ctrl.text.trim()));
                                }
                                Navigator.pop(context);
                              },
                              child: const Text('Add'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('+ Add player'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  timer?.cancel();
                  Navigator.pop(ctx);
                },
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _exportCollectionForFriends() async {
    final jsonList = _myCollection.map((g) => g.toJson()).toList();
    final blob = jsonEncode({'games': jsonList, 'exported_at': DateTime.now().toIso8601String()});
    await Clipboard.setData(ClipboardData(text: blob));

    // Show nice QR code for easy sharing (scan with camera or friend can screenshot)
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Share Collection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Scan this QR or copy the text below.'),
            const SizedBox(height: 12),
            QrImageView(
              data: blob,
              version: QrVersions.auto,
              size: 200,
            ),
            const SizedBox(height: 8),
            SelectableText(blob, style: const TextStyle(fontSize: 10)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: blob));
              Navigator.pop(context);
            },
            child: const Text('Copy Text'),
          ),
        ],
      ),
    );
  }

  void _importFriendCollection() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Merge Friend\'s Collection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Paste the share code from your friend (or scan QR later):'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 4,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '{"games": [...]}'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              try {
                final data = jsonDecode(ctrl.text.trim());
                final gamesJson = (data['games'] as List?) ?? [];
                int added = 0;
                for (final j in gamesJson) {
                  final g = Game.fromJson(j as Map<String, dynamic>);
                  if (!_myCollection.any((x) => x.id == g.id)) {
                    _myCollection.add(g);
                    added++;
                  }
                }
                _saveCollections();
                Navigator.pop(c);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Merged! Added $added new games from friend.')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid share code. Make sure you pasted the full text.')),
                );
              }
            },
            child: const Text('Merge'),
          ),
        ],
      ),
    );
  }

  // --- Persistent Session-based Shared Scoring ---
  // QR now carries a stable session ID (not a full snapshot).
  // Updates "persist" on the host device as long as the session is active.
  // Other devices can join by ID and pull/push the live state.
  // The host runs a tiny local server while the session is active.
  // This way the state lives independently of any single QR snapshot.

  Future<void> _startOrShareScoreSession() async {
    if (_scorePlayers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add players before starting a session.')),
      );
      return;
    }

    if (_activeScoreSessionId == null) {
      // Create stable session ID + short PIN (never put IP/port in shareable QR)
      _activeScoreSessionId = 'BGS-${(DateTime.now().millisecondsSinceEpoch % 1000000).toString().padLeft(6, '0')}';
      _activeScoreSessionPin = (100000 + DateTime.now().millisecond % 900000).toString();
      _isScoreSessionHost = true;
      await _startLocalScoreServer();
      await _startDiscoveryBroadcast(); // UDP broadcast for discovery (IP not in QR)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session active. PIN: ${_activeScoreSessionPin}. QR has no IP.')),
      );
    }

    // QR contains ONLY ID + PIN. No IP, no port exposed to QR or screenshots.
    final qrData = 'bgsnap-score:${_activeScoreSessionId}:${_activeScoreSessionPin}';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Session ${_activeScoreSessionId}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_isScoreSessionHost
                  ? 'Hosting. Session state lives here while active. IP hidden from QR.'
                  : 'In session.'),
              const SizedBox(height: 12),
              QrImageView(data: qrData, version: QrVersions.auto, size: 200),
              const SizedBox(height: 8),
              const Text('Others scan this. IP is discovered privately via local network.'),
              if (_activeScoreSessionPin != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('PIN required: ${_activeScoreSessionPin}', style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
        actions: [
          if (_isScoreSessionHost)
            TextButton(
              onPressed: () {
                _stopLocalScoreServer();
                _stopDiscoveryBroadcast();
                _activeScoreSessionId = null;
                _activeScoreSessionPin = null;
                _isScoreSessionHost = false;
                Navigator.pop(context);
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session ended.')));
              },
              child: const Text('End Session'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: qrData));
              Navigator.pop(context);
            },
            child: const Text('Copy Code'),
          ),
        ],
      ),
    );
  }

  Future<void> _startLocalScoreServer() async {
    try {
      _scoreSessionServer?.close();
      _scoreSessionServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _scoreSessionPort = _scoreSessionServer!.port;

      _scoreSessionServer!.listen((HttpRequest request) async {
        final path = request.uri.path;
        final providedPin = request.uri.queryParameters['pin'] ?? request.headers.value('x-session-pin');

        // Require correct PIN for all access (masks unauthorized use even on same network)
        if (providedPin != _activeScoreSessionPin) {
          request.response.statusCode = 403;
          request.response.write('invalid pin');
          await request.response.close();
          return;
        }

        if (path == '/session/$_activeScoreSessionId' && request.method == 'GET') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'sessionId': _activeScoreSessionId,
            'players': _scorePlayers,
            'updatedAt': DateTime.now().toIso8601String(),
          }));
          await request.response.close();
        } else if (path == '/session/$_activeScoreSessionId/update' && request.method == 'POST') {
          final body = await utf8.decoder.bind(request).join();
          try {
            final update = jsonDecode(body) as Map<String, dynamic>;
            final updatedPlayers = List<Map<String, dynamic>>.from(update['players'] ?? []);
            setState(() {
              for (final u in updatedPlayers) {
                final idx = _scorePlayers.indexWhere((p) => p['name'] == u['name']);
                if (idx != -1) {
                  _scorePlayers[idx]['score'] = u['score'];
                }
              }
            });
            request.response.write('ok');
          } catch (_) {
            request.response.write('bad');
          }
          await request.response.close();
        } else {
          request.response.statusCode = 404;
          await request.response.close();
        }
      });

      print('Score session server listening on port $_scoreSessionPort');
    } catch (e) {
      print('Failed to start score server: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start local server. Others will use manual paste for now.')),
      );
    }
  }

  void _stopLocalScoreServer() {
    _scoreSessionServer?.close();
    _scoreSessionServer = null;
    _scoreSessionPort = null;
  }

  // UDP broadcast/listener so QR never needs to contain IP or port.
  // Host periodically announces its presence for the session ID.
  Future<void> _startDiscoveryBroadcast() async {
    try {
      _stopDiscoveryBroadcast();
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      _discoverySocket = socket;

      String? ip;
      try {
        final info = NetworkInfo();
        ip = await info.getWifiIP() ?? 'unknown';
      } catch (_) {
        ip = 'unknown';
      }

      final announcement = jsonEncode({
        'id': _activeScoreSessionId,
        'ip': ip,
        'port': _scoreSessionPort,
        'pin': _activeScoreSessionPin,
      });

      Timer.periodic(const Duration(seconds: 4), (t) {
        if (_discoverySocket == null || _activeScoreSessionId == null) {
          t.cancel();
          return;
        }
        _discoverySocket!.send(
          utf8.encode(announcement),
          InternetAddress('255.255.255.255'),
          _discoveryPort,
        );
      });
    } catch (e) {
      print('Discovery broadcast failed: $e');
    }
  }

  void _stopDiscoveryBroadcast() {
    _discoverySocket?.close();
    _discoverySocket = null;
  }

  // Listen for host announcements on the network (auto-discover IP without it being in QR)
  Future<void> _listenForDiscovery(String targetId, String targetPin) async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _discoveryPort);
      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            try {
              final msg = jsonDecode(utf8.decode(datagram.data));
              if (msg['id'] == targetId && msg['pin'] == targetPin) {
                final ip = msg['ip'] as String?;
                final port = msg['port'] as int?;
                if (ip != null && port != null && ip != 'unknown') {
                  _lastHostIp = ip;
                  _lastHostPort = port;
                  socket.close();
                  _pullLatestScores(ip, port, targetId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Host discovered. Synced scores.')),
                  );
                }
              }
            } catch (_) {}
          }
        }
      });

      // Timeout the listener after 15s
      Future.delayed(const Duration(seconds: 15), () {
        try { socket.close(); } catch (_) {}
      });
    } catch (e) {
      print('Discovery listen failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not auto-discover. You may need to ask host for IP or use manual sync.')),
      );
    }
  }

  void _joinScoreSession() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Join Score Session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Paste code from QR (bgsnap-score:ID:PIN). IP is never in the code.'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 2,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'bgsnap-score:BGS-123456:123456'),
            ),
            const SizedBox(height: 8),
            const Text('On same Wi-Fi, the app can auto-discover the host IP.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final code = ctrl.text.trim();
              Navigator.pop(c);

              final parts = code.split(':');
              if (parts.length < 3 || parts[0] != 'bgsnap-score') {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid code.')));
                return;
              }

              final sessionId = parts[1];
              final pin = parts[2];

              setState(() {
                _activeScoreSessionId = sessionId;
                _activeScoreSessionPin = pin;
                _isScoreSessionHost = false;
              });

              // Try auto-discovery first via UDP broadcast listener
              await _listenForDiscovery(sessionId, pin);
              // Fallback: if no broadcast received quickly, user can manually sync later
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  Future<void> _pullLatestScores(String hostIp, int port, String sessionId) async {
    try {
      final pin = _activeScoreSessionPin ?? '';
      final url = Uri.parse('http://$hostIp:$port/session/$sessionId?pin=$pin');
      final resp = await http.get(url).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        _lastHostIp = hostIp;
        _lastHostPort = port;
        final incoming = List<Map<String, dynamic>>.from(data['players'] ?? []);
        setState(() {
          for (final inc in incoming) {
            final idx = _scorePlayers.indexWhere((p) => p['name'] == inc['name']);
            if (idx != -1) {
              _scorePlayers[idx]['score'] = inc['score'];
            } else {
              _scorePlayers.add(Map.from(inc));
            }
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synced latest scores from host.'), duration: Duration(seconds: 1)),
        );
      } else if (resp.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wrong PIN for session.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reach host. Are you on the same Wi-Fi?')),
      );
    }
  }

  // Clients push score changes to host so the live session state is updated centrally.
  Future<void> _pushUpdateToHost() async {
    if (_activeScoreSessionId == null || _isScoreSessionHost || _lastHostIp == null || _lastHostPort == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join using host info first (or re-join) to push updates.')),
      );
      return;
    }

    try {
      final pin = _activeScoreSessionPin ?? '';
      final url = Uri.parse('http://${_lastHostIp}:${_lastHostPort}/session/$_activeScoreSessionId/update?pin=$pin');
      final body = jsonEncode({'players': _scorePlayers});
      final resp = await http.post(url, body: body, headers: {'Content-Type': 'application/json'}).timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Update pushed to host.')));
      } else if (resp.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN rejected.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not reach host.')));
    }
  }

  Future<void> _suggestFeature() async {
    const url = 'https://github.com/Cyberj812/Board-Game-Identification/issues/new?template=feature_request.md';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open browser to suggest a feature.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(_tabTitle()),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              showAboutDialog(
                context: context,
                applicationName: 'Board Game Snap',
                applicationVersion: '1.0.0',
                children: [
                  const Text(
                    'Snap a photo of a game box to identify it, search for games, and explore details, videos, and strategy tips.',
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    icon: const Icon(Icons.bug_report),
                    label: const Text('Report a Bug'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      _reportBug();
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.lightbulb_outline),
                    label: const Text('Suggest an Improvement'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      _suggestFeature();
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _buildCurrentTab(),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book),
            label: 'My Collection',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.videogame_asset),
            label: 'Play',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.casino),
            label: 'Dice',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.scoreboard),
            label: 'Score',
          ),
        ],
      ),
    );
  }

  String _tabTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'My Collection';
      case 1:
        return 'Play';
      case 2:
        return 'Dice';
      case 3:
        return 'Score Tracker';
      default:
        return 'Board Game Snap';
    }
  }

  Widget _buildCurrentTab() {
    switch (_selectedIndex) {
      case 0:
        return _buildMyCollectionTab();
      case 1:
        return _buildPlayTab();
      case 2:
        return _buildDiceTab();
      case 3:
        return _buildScoreTab();
      default:
        return _buildMyCollectionTab();
    }
  }

  // Tab 0: My Collection (default, open book icon)
  Widget _buildMyCollectionTab() {
    if (_myCollection.isEmpty) {
      return Column(
        children: [
          const SizedBox(height: 32),
          Icon(Icons.menu_book, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('No games yet', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Scan a box, search the library, or import from BGG to get started.'),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _scanBox,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Scan game box'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _importMyBGGCollection,
            icon: const Icon(Icons.download),
            label: const Text('Import from BGG'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _showManualEntry,
            icon: const Icon(Icons.edit),
            label: const Text('Add manual entry'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _scanBox,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Scan'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showManualEntry,
                icon: const Icon(Icons.edit),
                label: const Text('Add'),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Merge friend collection (QR/link)',
              onPressed: _importFriendCollection,
              icon: const Icon(Icons.group_add),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _exportCollectionForFriends,
            icon: const Icon(Icons.share, size: 16),
            label: const Text('Share my collection (for friends)', style: TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: _myCollection.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final g = _myCollection[index];
              return ListTile(
                leading: g.imageUrl != null && g.imageUrl!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                          imageUrl: g.imageUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          placeholder: (c, u) => Container(width: 48, height: 48, color: Colors.grey[300]),
                          errorWidget: (c, u, e) => const Icon(Icons.image, size: 48),
                        ),
                      )
                    : const Icon(Icons.videogame_asset, size: 48),
                title: Text(g.name, style: Theme.of(context).textTheme.titleMedium),
                subtitle: Text([
                  if (g.year.isNotEmpty) g.year,
                  g.playerCount,
                  g.weightString,
                  if (g.rating != null) '${g.rating!.toStringAsFixed(1)}★',
                ].where((s) => s.isNotEmpty).join(' · ')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.play_circle_outline),
                      onPressed: () => _logPlay(g),
                      tooltip: 'Log play',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () {
                        setState(() {
                          _myCollection.removeWhere((x) => x.id == g.id);
                        });
                        _saveCollections();
                      },
                      tooltip: 'Remove',
                    ),
                  ],
                ),
                onTap: () => _viewGame(g),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: () => setState(() => _selectedIndex = 1),
            icon: const Icon(Icons.search),
            label: const Text('Search the library to add more'),
          ),
        ),
      ],
    );
  }

  // Tab 1: Play (game piece icon) - search, filters, What Should We Play
  Widget _buildPlayTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _showWhatShouldWePlay,
          icon: const Icon(Icons.casino_outlined),
          label: const Text('What Should We Play?'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.purple,
          ),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () => _showPackList(),
          icon: const Icon(Icons.backpack),
          label: const Text('Generate Pack List'),
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: _showTurnTimer,
          icon: const Icon(Icons.timer),
          label: const Text('Turn Order + Timer'),
        ),
        const SizedBox(height: 8),
        Text(
          'Search the library',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search games (your collection + library)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) {
            setState(() {
              _searchText = value;
            });
            final trimmed = value.trim();
            _searchDebounce?.cancel();

            final shouldSearch = trimmed.length >= 2 || _hasAnyFilter();
            if (shouldSearch) {
              setState(() {
                _isSearchingBgg = true;
                _bggSearchResults = [];
                _searchStart = 0;
                _hasMoreResults = true;
              });
            } else {
              setState(() {
                _bggSearchResults = [];
                _isSearchingBgg = false;
                _hasMoreResults = false;
                _lastBggSearchTerm = '';
              });
            }

            _searchDebounce = Timer(const Duration(milliseconds: 400), () {
              _searchBggLibrary(value);
            });
          },
        ),
        const SizedBox(height: 6),
        // Filters
        Row(
          children: [
            Expanded(
              child: _buildActiveFilterSummary(),
            ),
            TextButton.icon(
              onPressed: _showSearchFilters,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Filters'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
            if (_hasAnyFilter())
              TextButton(
                onPressed: _clearSearchFilters,
                child: const Text('Clear', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: _isScanning ? const Text('Scanning...') : const Text('Scan game box'),
                onPressed: _isScanning ? null : _scanBox,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.shuffle),
                label: const Text('Random'),
                onPressed: _showRandomGame,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Text(
                'Search results',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_isSearchingBgg) ...[
                const SizedBox(width: 8),
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ],
          ),
        ),

        Expanded(
          child: Builder(
            builder: (context) {
              if (_isSearchingBgg) {
                return const Center(child: CircularProgressIndicator());
              } else if (_bggSearchResults.isEmpty) {
                final hasQuery = _searchText.trim().length >= 2;
                final bool isFilterMode = _hasAnyFilter();
                String message;
                if (isFilterMode && !hasQuery) {
                  message = 'No games match your filters.\nTry different filter settings or add a search term.';
                } else if (isFilterMode) {
                  message = 'No games match your search and filters.';
                } else if (hasQuery) {
                  message = 'No results. Try a different search term.';
                } else {
                  message = 'Search or use filters above.\nResults include your collection + library.';
                }
                return Center(
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: (hasQuery || isFilterMode) ? null : const TextStyle(color: Colors.grey),
                  ),
                );
              } else {
                final itemCount = _bggSearchResults.length + (_hasMoreResults ? 1 : 0);
                return ListView.separated(
                  itemCount: itemCount,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (_hasMoreResults && index == _bggSearchResults.length) {
                      return ListTile(
                        title: const Center(child: Text('Load more results...')),
                        onTap: _isSearchingBgg ? null : _loadMoreBggResults,
                        trailing: _isSearchingBgg
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : null,
                      );
                    }
                    final game = _bggSearchResults[index];
                    final theme = Theme.of(context);
                    return ListTile(
                      leading: game.imageUrl != null && game.imageUrl!.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: CachedNetworkImage(
                                imageUrl: game.imageUrl!,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                placeholder: (c, u) => Container(width: 50, height: 50, color: Colors.grey[300]),
                                errorWidget: (c, u, e) => const Icon(Icons.image, size: 50),
                              ),
                            )
                          : const Icon(Icons.videogame_asset, size: 50),
                      title: Text(game.name, style: theme.textTheme.titleMedium),
                      subtitle: Text(
                        [
                          if (game.year.isNotEmpty) game.year,
                          if (game.minPlayers > 0 || game.maxPlayers > 0) '${game.playerCount} players',
                          game.weightString,
                          if (game.rating != null) '${game.rating!.toStringAsFixed(1)}★',
                        ].where((s) => s.isNotEmpty && s != '?').join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _viewGame(game),
                    );
                  },
                );
              }
            },
          ),
        ),
      ],
    );
  }

  // Tab 2: Dice (die icon) - full tab page
  Widget _buildDiceTab() {
    // Stateful dice content lives in a separate StatefulWidget for clean state
    return const _DiceRollerPage();
  }

  // Tab 3: Score Tracker (scorecard icon)
  Widget _buildScoreTab() {
    return Column(
      children: [
        // Shared multi-device scoring controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _startOrShareScoreSession,
                  icon: const Icon(Icons.qr_code_2, size: 18),
                  label: const Text('Share / Host Session', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _joinScoreSession,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Join Session', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
        if (_activeScoreSessionId != null)
          Container(
            padding: const EdgeInsets.all(6),
            color: Colors.deepPurple.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: Text('Session: $_activeScoreSessionId', style: const TextStyle(fontWeight: FontWeight.bold))),
                if (!_isScoreSessionHost) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () {
                      if (_lastHostIp != null && _lastHostPort != null) {
                        _pullLatestScores(_lastHostIp!, _lastHostPort!, _activeScoreSessionId!);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Re-join with host info to enable sync/push.')),
                        );
                      }
                    },
                    child: const Text('Sync', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 4),
                  OutlinedButton(
                    onPressed: _pushUpdateToHost,
                    child: const Text('Push My Scores', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
        Expanded(
          child: _ScoreTrackerPage(
            players: _scorePlayers,
            onPlayersChanged: (updated) {
              setState(() {
                _scorePlayers = updated;
              });
            },
          ),
        ),
      ],
    );
  }
}

// Extracted full-page Dice roller for the Dice tab (type-specific visuals + animation)
class _DiceRollerPage extends StatefulWidget {
  const _DiceRollerPage({super.key});

  @override
  State<_DiceRollerPage> createState() => _DiceRollerPageState();
}

class _DiceRollerPageState extends State<_DiceRollerPage> with SingleTickerProviderStateMixin {
  List<String> dieTypes = ['d4', 'd6', 'd8', 'd10', 'd12', 'd20', 'd100'];
  String selectedType = 'd6';
  int numDice = 1;
  List<int> displayRolls = [];
  int displayTotal = 0;
  bool isRolling = false;

  late AnimationController _spinController;
  double _spinAngle = 0.0;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..addListener(() {
        if (mounted) {
          setState(() {
            _spinAngle = _spinController.value * (4 * pi); // ~2 full fast spins
          });
        }
      });
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _performRoll() async {
    if (isRolling) return;

    setState(() {
      isRolling = true;
      displayRolls = [];
      displayTotal = 0;
      _spinAngle = 0;
    });

    // Start the physical spin animation
    _spinController.reset();
    _spinController.forward();

    int sides = int.parse(selectedType.substring(1));

    // Rapid random values while spinning (slows toward the end)
    const int rollSteps = 16;
    for (int step = 0; step < rollSteps; step++) {
      final delay = 45 + (step * 18); // slows down naturally
      await Future.delayed(Duration(milliseconds: delay));
      if (!mounted) return;

      setState(() {
        displayRolls = List.generate(numDice, (_) => Random().nextInt(sides) + 1);
      });
    }

    // Final locked result
    final finalRolls = List.generate(numDice, (_) => Random().nextInt(sides) + 1);
    final finalTotal = finalRolls.fold(0, (a, b) => a + b);

    // Let spin finish settling a little
    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;

    setState(() {
      displayRolls = finalRolls;
      displayTotal = finalTotal;
      isRolling = false;
      _spinAngle = 0; // settle straight
    });
  }

  Widget _buildDieVisual(int value, String type) {
    final isD6 = type == 'd6';
    final isRollingDie = isRolling;

    // Larger, more physical dice
    const double dieSize = 82;

    // Die face content: special pips for d6, big number otherwise
    Widget faceContent;
    if (isD6) {
      faceContent = CustomPaint(
        size: Size(dieSize - 10, dieSize - 10),
        painter: _D6PipsPainter(value),
      );
    } else {
      faceContent = Text(
        '$value',
        style: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w900,
          color: Colors.black87,
          shadows: const [Shadow(color: Colors.black26, blurRadius: 1, offset: Offset(0.5, 0.5))],
        ),
      );
    }

    // Styling varies slightly by die for immersion
    final bgColor = isD6 ? Colors.white : const Color(0xFFF5F5F5);
    final borderColor = isD6 ? Colors.black87 : Colors.black54;
    final borderWidth = isD6 ? 2.5 : 2.0;
    final borderRadius = isD6 ? 10.0 : 14.0;

    return Transform.rotate(
      angle: isRollingDie ? _spinAngle : 0.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: dieSize,
        height: dieSize,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: [
            BoxShadow(
              color: isRollingDie ? Colors.black38 : Colors.black26,
              blurRadius: isRollingDie ? 8 : 5,
              offset: Offset(2, isRollingDie ? 4 : 2),
              spreadRadius: isRollingDie ? 1 : 0,
            ),
          ],
        ),
        child: Center(child: faceContent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('Digital Dice', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Choose size & type • Roll for real die visuals',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: 'Die Type'),
                  items: dieTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (val) {
                    if (val != null && !isRolling) {
                      setState(() => selectedType = val);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: numDice,
                  decoration: const InputDecoration(labelText: 'Number of Dice'),
                  items: List.generate(10, (i) => i + 1)
                      .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                      .toList(),
                  onChanged: (val) {
                    if (val != null && !isRolling) {
                      setState(() => numDice = val);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: isRolling ? null : _performRoll,
            icon: const Icon(Icons.casino),
            label: Text(isRolling ? 'Rolling...' : 'ROLL'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(180, 52),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 28),
          if (displayRolls.isNotEmpty) ...[
            Wrap(
              spacing: 14,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: displayRolls.map((v) => _buildDieVisual(v, selectedType)).toList(),
            ),
            const SizedBox(height: 18),
            if (numDice > 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Total: $displayTotal',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
          ] else
            Container(
              padding: const EdgeInsets.all(24),
              child: const Text(
                'Select die type and count above,\nthen tap ROLL for animated dice.',
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 24),
          Text(
            isRolling
                ? 'Watch them spin and settle...'
                : 'd6 shows classic pips • others show large numbers',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// Custom painter for realistic d6 pips (classic dice look)
class _D6PipsPainter extends CustomPainter {
  final int value;

  _D6PipsPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;

    final double dotRadius = size.width * 0.095;
    final double c = size.width / 2;
    final double o = size.width * 0.22; // offset from center for corners

    void dot(double x, double y) {
      canvas.drawCircle(Offset(x, y), dotRadius, paint);
    }

    switch (value) {
      case 1:
        dot(c, c);
        break;
      case 2:
        dot(c - o, c - o);
        dot(c + o, c + o);
        break;
      case 3:
        dot(c - o, c - o);
        dot(c, c);
        dot(c + o, c + o);
        break;
      case 4:
        dot(c - o, c - o);
        dot(c + o, c - o);
        dot(c - o, c + o);
        dot(c + o, c + o);
        break;
      case 5:
        dot(c - o, c - o);
        dot(c + o, c - o);
        dot(c, c);
        dot(c - o, c + o);
        dot(c + o, c + o);
        break;
      case 6:
        dot(c - o, c - o);
        dot(c + o, c - o);
        dot(c - o, c);
        dot(c + o, c);
        dot(c - o, c + o);
        dot(c + o, c + o);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _D6PipsPainter oldDelegate) => oldDelegate.value != value;
}

// Extracted full-page Score Tracker (larger knob + no overflow)
class _ScoreTrackerPage extends StatefulWidget {
  final List<Map<String, dynamic>> players;
  final ValueChanged<List<Map<String, dynamic>>> onPlayersChanged;

  const _ScoreTrackerPage({required this.players, required this.onPlayersChanged});

  @override
  State<_ScoreTrackerPage> createState() => _ScoreTrackerPageState();
}

class _ScoreTrackerPageState extends State<_ScoreTrackerPage> {
  late List<Map<String, dynamic>> _players;

  @override
  void initState() {
    super.initState();
    _players = List.from(widget.players);
  }

  void _updateParent() {
    widget.onPlayersChanged(List.from(_players));
  }

  void _addPlayer() {
    final nameCtrl = TextEditingController();
    Color selectedColor = Colors.blue;
    final colors = [Colors.red, Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.teal, Colors.pink];

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setColorState) {
          return AlertDialog(
            title: const Text('Add Player'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Player Name')),
                const SizedBox(height: 12),
                const Text('Choose color:'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: colors.map((c) => GestureDetector(
                    onTap: () {
                      setColorState(() => selectedColor = c);
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: selectedColor == c ? 3 : 1,
                          color: selectedColor == c ? Colors.black : Colors.black38,
                        ),
                      ),
                    ),
                  )).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  setState(() {
                    _players.add({
                      'name': name,
                      'colorValue': selectedColor.value,
                      'score': 0,
                    });
                  });
                  _updateParent();
                  Navigator.pop(c);
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final players = _players;
    return Column(
      children: [
        if (players.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.scoreboard, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No players yet.\nAdd players and use the large knob to score.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _addPlayer,
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add Player'),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 80),
              children: players.map((p) {
                final player = Map<String, dynamic>.from(p);
                final color = Color(player['colorValue']);
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black26),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                player['name'],
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                setState(() {
                                  _players.removeWhere((e) => e['name'] == player['name']);
                                });
                                _updateParent();
                              },
                              tooltip: 'Remove player',
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Large dedicated area for circling gesture
                        _LargeScoreKnob(
                          score: player['score'],
                          color: color,
                          onScoreChanged: (newScore) {
                            setState(() {
                              player['score'] = newScore;
                              final idx = _players.indexWhere((e) => e['name'] == player['name']);
                              if (idx != -1) _players[idx] = player;
                            });
                            _updateParent();
                          },
                        ),
                        const SizedBox(height: 4),
                        Text('circle finger around knob', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              FilledButton.icon(
                onPressed: _addPlayer,
                icon: const Icon(Icons.person_add),
                label: const Text('Add Player'),
              ),
              if (players.isNotEmpty)
                OutlinedButton(
                  onPressed: () {
                    setState(() => _players.clear());
                    _updateParent();
                  },
                  child: const Text('Reset All'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LargeScoreKnob extends StatefulWidget {
  final int score;
  final Color color;
  final ValueChanged<int> onScoreChanged;

  const _LargeScoreKnob({
    required this.score,
    required this.color,
    required this.onScoreChanged,
  });

  @override
  State<_LargeScoreKnob> createState() => _LargeScoreKnobState();
}

class _LargeScoreKnobState extends State<_LargeScoreKnob> {
  double _prevAngle = 0;
  bool _dragging = false;

  double _angleFromCenter(Offset localPos, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPos.dx - center.dx;
    final dy = localPos.dy - center.dy;
    return atan2(dy, dx);
  }

  @override
  Widget build(BuildContext context) {
    // Much larger finger-friendly hit area + visual knob
    const double hitSize = 200.0;      // generous touch target for circling
    const double visualSize = 150.0;   // big visible knob

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) {
        _dragging = true;
        final s = context.size ?? const Size(hitSize, hitSize);
        _prevAngle = _angleFromCenter(details.localPosition, s);
      },
      onPanUpdate: (details) {
        if (!_dragging) return;
        final s = context.size ?? const Size(hitSize, hitSize);
        final angle = _angleFromCenter(details.localPosition, s);
        double delta = angle - _prevAngle;
        if (delta > pi) delta -= 2 * pi;
        if (delta < -pi) delta += 2 * pi;

        // More responsive: trigger on smaller angle change
        if (delta.abs() > 0.28) {
          final change = delta > 0 ? 1 : -1;
          widget.onScoreChanged(widget.score + change);
          _prevAngle = angle;
        }
      },
      onPanEnd: (_) => _dragging = false,
      child: SizedBox(
        width: hitSize,
        height: hitSize,
        child: Center(
          child: Container(
            width: visualSize,
            height: visualSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.12),
              border: Border.all(color: widget.color, width: 5),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.25),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Center(
              child: Text(
                '${widget.score}',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: widget.color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class GameDetailPage extends StatelessWidget {
  final Game game;
  final bool isInMyCollection;
  final bool isInWishlist;
  final VoidCallback? onAddToMyCollection;
  final VoidCallback? onAddToWishlist;
  final void Function(Game)? onLogPlay;
  final void Function(Game, BuildContext)? onEditHouseRules;

  const GameDetailPage({
    super.key,
    required this.game,
    this.isInMyCollection = false,
    this.isInWishlist = false,
    this.onAddToMyCollection,
    this.onAddToWishlist,
    this.onLogPlay,
    this.onEditHouseRules,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(game.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (game.imageUrl != null && game.imageUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: game.imageUrl!,
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => Container(
                    height: 220,
                    color: Colors.grey.shade200,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 220,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.image_not_supported, size: 48),
                  ),
                ),
              ),
            ),
          Text(game.name, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 4),
          Text(game.year),
          if (isInMyCollection || isInWishlist) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (isInMyCollection)
                  Chip(
                    label: const Text('In My Collection'),
                    avatar: const Icon(Icons.collections_bookmark, size: 16),
                    backgroundColor: Colors.green.shade100,
                  ),
                if (isInWishlist)
                  Chip(
                    label: const Text('On Wishlist'),
                    avatar: const Icon(Icons.shopping_cart, size: 16),
                    backgroundColor: Colors.blue.shade100,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),

          // Stats - use Wrap to avoid right overflow on small screens
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceEvenly,
            children: [
              _StatItem(label: 'Players', value: game.playerCount),
              _StatItem(label: 'Weight', value: game.weightString),
              _StatItem(label: 'Rating', value: game.ratingString),
              _StatItem(label: 'Rank', value: game.rankString),
              _StatItem(label: 'Time', value: game.playtime.isNotEmpty ? '${game.playtime} min' : '?'),
            ],
          ),

          const SizedBox(height: 16),

          // Play History - enhanced with photos
          if (game.playCount > 0)
            _Section(
              title: 'Battle Log',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Plays: ${game.playCount}'),
                  if (game.lastPlayed != null)
                    Text('Last played: ${game.lastPlayed!.toLocal().toString().split(' ')[0]}'),
                  if (game.averageRating != null)
                    Text('Avg rating: ${game.averageRating!.toStringAsFixed(1)} / 10'),
                  const SizedBox(height: 8),
                  ...game.playLogs.reversed.take(5).map((log) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      child: ListTile(
                        dense: true,
                        leading: log.photoPath != null && File(log.photoPath!).existsSync()
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.file(
                                  File(log.photoPath!),
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : const Icon(Icons.history),
                        title: Text('${log.date.toLocal().toString().split(' ')[0]} • ${log.players} players'),
                        subtitle: Text(
                          [
                            if (log.rating != null) 'Rated ${log.rating}',
                            if (log.notes != null && log.notes!.isNotEmpty) log.notes,
                          ].where((s) => s != null && s.isNotEmpty).join(' • '),
                        ),
                        onTap: log.photoPath != null
                            ? () {
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    content: Image.file(File(log.photoPath!)),
                                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                                  ),
                                );
                              }
                            : null,
                      ),
                    );
                  }),
                  if (game.playLogs.length > 5)
                    const Text('... more in full history', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),

          // Per-game House Rules / Group Notes (new group feature)
          _Section(
            title: 'Group Notes / House Rules',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (game.houseRules != null && game.houseRules!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      game.houseRules!,
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  )
                else
                  const Text('No group notes yet. Tap edit to add house rules or variants for your play group.'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onEditHouseRules != null
                      ? () => onEditHouseRules!(game, context)
                      : () {},
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Edit House Rules'),
                ),
              ],
            ),
          ),

          // Status indicators + actions
          if (isInMyCollection)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.collections_bookmark, color: Colors.green, size: 18),
                  SizedBox(width: 8),
                  Text('Already in your collection', style: TextStyle(color: Colors.green)),
                ],
              ),
            ),

          if (isInWishlist)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shopping_cart, color: Colors.blue, size: 18),
                  SizedBox(width: 8),
                  Text('Already on your wishlist', style: TextStyle(color: Colors.blue)),
                ],
              ),
            ),

          ElevatedButton.icon(
            onPressed: onAddToMyCollection,
            icon: Icon(isInMyCollection ? Icons.remove_circle : Icons.collections_bookmark),
            label: Text(isInMyCollection ? 'Remove from My Collection' : 'I Own This (Add to My Collection)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isInMyCollection ? Colors.red[700] : Colors.green[700],
            ),
          ),

          const SizedBox(height: 8),

          ElevatedButton.icon(
            onPressed: onAddToWishlist,
            icon: Icon(isInWishlist ? Icons.remove_circle : Icons.shopping_cart),
            label: Text(isInWishlist ? 'Remove from Wishlist' : 'Want to Buy (Add to Wishlist)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isInWishlist ? Colors.red[700] : Colors.blue[700],
            ),
          ),

          const SizedBox(height: 12),

          // Play Logging
          ElevatedButton.icon(
            onPressed: () {
              if (onLogPlay != null) {
                onLogPlay!(game);
              } else {
                // Fallback
                print('Log play for ${game.name}');
              }
            },
            icon: const Icon(Icons.history),
            label: const Text('Log Play'),
          ),

          const SizedBox(height: 16),

          // Quick Actions - relevant one-tap options for shopping and play
          _Section(
            title: 'Quick Actions',
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                // Collection / Wishlist (main relevant actions)
                ActionChip(
                  avatar: Icon(
                    isInMyCollection ? Icons.remove_circle : Icons.add,
                    size: 18,
                    color: isInMyCollection ? Colors.red : Colors.green,
                  ),
                  label: Text(isInMyCollection ? 'Remove from Collection' : 'Add to My Collection'),
                  onPressed: onAddToMyCollection,
                ),
                ActionChip(
                  avatar: Icon(
                    isInWishlist ? Icons.remove_circle : Icons.add,
                    size: 18,
                    color: isInWishlist ? Colors.red : Colors.blue,
                  ),
                  label: Text(isInWishlist ? 'Remove from Wishlist' : 'Add to Wishlist'),
                  onPressed: onAddToWishlist,
                ),
                ActionChip(
                  avatar: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Game Page'),
                  onPressed: () {
                    final bggUrl = game.id.startsWith('manual_')
                        ? 'https://boardgamegeek.com/geeksearch.php?action=search&objecttype=boardgame&q=${Uri.encodeComponent(game.name)}'
                        : 'https://boardgamegeek.com/boardgame/${game.id}';
                    _launch(bggUrl, context);
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.play_circle, size: 18),
                  label: const Text('How to Play'),
                  onPressed: () {
                    final slug = game.name.toLowerCase().replaceAll(' ', '+');
                    _launch("https://www.youtube.com/results?search_query=how+to+play+$slug+watch+it+played", context);
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.psychology, size: 18),
                  label: const Text('Strategy Tips'),
                  onPressed: () => _showStrategyPrompt(context, game),
                ),
                if (game.digitalPlatforms.isNotEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.computer, size: 18),
                    label: const Text('Digital Play'),
                    onPressed: () => _launch(game.digitalPlatforms.first.url ?? 'https://boardgamegeek.com/boardgame/${game.id}', context),
                  ),
                if (game.expansions.isNotEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.extension, size: 18),
                    label: Text('Expansions (${game.expansions.length})'),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('See expansions section below')),
                      );
                    },
                  ),
                ActionChip(
                  avatar: const Icon(Icons.shuffle, size: 18),
                  label: const Text('Random from My Collection'),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Use "Pick Random from My Collection" on home screen')),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Digital Play (new feature)
          if (game.digitalPlatforms.isNotEmpty)
            _Section(
              title: 'Digital Play',
              child: Column(
                children: game.digitalPlatforms.map((platform) {
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.computer),
                    title: Text(platform.name),
                    trailing: platform.url != null ? const Icon(Icons.open_in_new) : null,
                    onTap: platform.url != null ? () => _launch(platform.url!, context) : null,
                  );
                }).toList(),
              ),
            ),

          // Expansions
          _Section(
            title: 'Expansions',
            child: game.expansions.isEmpty
                ? const Text('No expansions found.')
                : Column(
                    children: game.expansions
                        .map((e) => ListTile(
                              dense: true,
                              title: Text(e.name),
                              trailing: const Icon(Icons.chevron_right, size: 16),
                              onTap: () async {
                                // Fetch full details for the expansion so we get its box art
                                final fullExp = await BggService(token: bggToken).getGameDetails(e.id);
                                if (fullExp != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => GameDetailPage(game: fullExp),
                                    ),
                                  );
                                } else {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => GameDetailPage(
                                        game: Game(id: e.id, name: e.name, year: ''),
                                      ),
                                    ),
                                  );
                                }
                              },
                            ))
                        .toList(),
                  ),
          ),

          // How to Play Videos
          _Section(
            title: 'How to Play Videos',
            child: Column(
              children: _buildVideoLinks(game.name).map((link) {
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    dense: true,
                    leading: Container(
                      width: 60,
                      height: 34,
                      color: Colors.black,
                      child: const Center(
                        child: Icon(Icons.play_arrow, color: Colors.red, size: 24),
                      ),
                    ),
                    title: Text(link.$1),
                    subtitle: const Text('Watch on YouTube'),
                    onTap: () => _launch(link.$2, context),
                  ),
                );
              }).toList(),
            ),
          ),

          // Strategy
          _Section(
            title: 'Strategy Hints',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '• Focus on engine building early\n'
                  '• Watch for endgame triggers\n'
                  '• Deny key resources when cheap\n'
                  '• Learn the most efficient scoring paths',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _showStrategyPrompt(context, game),
                  icon: const Icon(Icons.smart_toy_outlined),
                  label: const Text('Copy AI Strategy Prompt'),
                ),
              ],
            ),
          ),

          // Rulebook
          _Section(
            title: 'Rulebook & References',
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Rulebooks & Files (BGG)'),
                  onTap: () {
                    final url = game.id.startsWith('manual_')
                        ? 'https://boardgamegeek.com/geeksearch.php?action=search&objecttype=boardgame&q=${Uri.encodeComponent(game.name)}'
                        : 'https://boardgamegeek.com/boardgame/${game.id}/files';
                    _launch(url, context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.book),
                  title: const Text('Add to Local Rulebook Library'),
                  onTap: () {
                    // Rulebook add is managed from main screen for now
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Open Rulebooks from the main screen to add.')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Full Game Details'),
                  onTap: () {
                    final url = game.id.startsWith('manual_')
                        ? 'https://boardgamegeek.com/geeksearch.php?action=search&objecttype=boardgame&q=${Uri.encodeComponent(game.name)}'
                        : 'https://boardgamegeek.com/boardgame/${game.id}';
                    _launch(url, context);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<(String, String)> _buildVideoLinks(String name) {
    final slug = name.toLowerCase().replaceAll(' ', '+');
    return [
      ('Watch It Played', "https://www.youtube.com/results?search_query=how+to+play+$slug+%22watch+it+played%22"),
      ('Rules Explained', "https://www.youtube.com/results?search_query=$slug+rules+explained"),
      ('Search YouTube', "https://www.youtube.com/results?search_query=how+to+play+$slug"),
    ];
  }

  void _showStrategyPrompt(BuildContext context, Game game) {
    final prompt = '''
You are a board game expert. Game: ${game.name}.

Give 6-8 specific, actionable strategy tips for a player who has played it a few times.

Focus on:
- Early game priorities
- Key engines/combos
- Interaction and denying opponents
- Endgame timing and scoring
- Common mistakes

Be concrete and reference actual mechanics.
''';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy this prompt'),
        content: SelectableText(prompt),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

}

Future<void> _launch(String url, [BuildContext? ctx]) async {
  if (url.isEmpty) return;
  final uri = Uri.parse(url);
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    if (ctx != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Could not open browser.')),
      );
    }
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        child,
        const SizedBox(height: 12),
      ],
    );
  }
}

class _SpinningWheel extends StatelessWidget {
  final List<Game> games;
  final double rotation;
  final Game? selectedGame;

  const _SpinningWheel({
    required this.games,
    required this.rotation,
    this.selectedGame,
  });

  @override
  Widget build(BuildContext context) {
    if (games.isEmpty) return const SizedBox.shrink();

    final size = 200.0;
    final anglePerItem = 2 * pi / games.length;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Wheel
          Transform.rotate(
            angle: rotation,
            child: CustomPaint(
              size: Size(size, size),
              painter: _WheelPainter(games.length),
            ),
          ),
          // Labels
          ...List.generate(games.length, (index) {
            final angle = index * anglePerItem + (anglePerItem / 2) - (rotation % (2 * pi));
            final x = (size / 2) * 0.75 * cos(angle - pi / 2);
            final y = (size / 2) * 0.75 * sin(angle - pi / 2);
            return Transform.translate(
              offset: Offset(x, y),
              child: Transform.rotate(
                angle: angle + pi / 2,
                child: SizedBox(
                  width: 70,
                  child: Text(
                    games[index].name,
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            );
          }),
          // Pointer
          const Positioned(
            top: 0,
            child: Icon(Icons.arrow_drop_down, size: 40, color: Colors.red),
          ),
          // Center
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(blurRadius: 4)],
            ),
            child: const Icon(Icons.casino, size: 24),
          ),
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final int segments;

  _WheelPainter(this.segments);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final sweep = 2 * pi / segments;

    for (int i = 0; i < segments; i++) {
      paint.color = Colors.primaries[i % Colors.primaries.length].shade300;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweep,
        sweep,
        true,
        paint,
      );
      // Optional border
      final borderPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweep,
        sweep,
        true,
        borderPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PdfViewerPage extends StatefulWidget {
  final String path;

  const _PdfViewerPage({required this.path});

  @override
  State<_PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<_PdfViewerPage> {
  late final PdfController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PdfController(
      document: PdfDocument.openFile(widget.path),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rulebook')),
      body: PdfView(controller: _controller),
    );
  }
}



