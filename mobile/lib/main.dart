import 'package:flutter/material.dart';
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
  bool _buildCollectionMode = false; // For now, keep but we won't auto-add

  // BGG library search
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
  final _bgg = BggService();

  late ConfettiController _confettiController;
  final AudioPlayer _audioPlayer = AudioPlayer();

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
    super.dispose();
  }

  Future<void> _loadCollection() async {
    final prefs = await SharedPreferences.getInstance();
    final collectionJson = prefs.getStringList('myCollection') ?? [];
    final wishlistJson = prefs.getStringList('wishlist') ?? [];
    setState(() {
      _myCollection = collectionJson
          .map((jsonStr) => Game.fromJson(jsonDecode(jsonStr)))
          .toList();
      _wishlist = wishlistJson
          .map((jsonStr) => Game.fromJson(jsonDecode(jsonStr)))
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
  }



  // Levenshtein distance for typo tolerance (small edit distance = close match)
  int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List.filled(t.length + 1, 0);
    List<int> v1 = List.filled(t.length + 1, 0);

    for (int i = 0; i <= t.length; i++) v0[i] = i;

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        int cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = [
          v1[j] + 1,
          v0[j + 1] + 1,
          v0[j] + cost
        ].reduce((a, b) => a < b ? a : b);
      }
      final temp = v0;
      v0 = v1;
      v1 = temp;
    }
    return v0[t.length];
  }

  bool _fuzzyMatch(String name, String query, {int maxDist = 2}) {
    final n = name.toLowerCase().trim();
    final q = query.toLowerCase().trim();
    if (n.isEmpty || q.isEmpty) return false;
    if (n.contains(q) || q.contains(n)) return true;
    return _levenshtein(n, q) <= maxDist;
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
    final futures = partials.map((g) async {
      try {
        final d = await _bgg.getGameDetails(g.id);
        return d ?? g;
      } catch (_) {
        return g;
      }
    });
    return await Future.wait(futures);
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

      // Enrich only the first ~15-20 so we don't hammer BGG with dozens of /thing calls at once
      // (rate limits were likely breaking searches). Stubs for the rest still appear in results
      // (they pass filters if no stat data, and hydrate on tap).
      final toEnrich = rawResults.take(18).toList();
      final enrichedTop = await _enrichGames(toEnrich);

      // Merge enriched data back into the full raw list (preserve order and all results)
      final enriched = List<Game>.from(rawResults);
      for (final e in enrichedTop) {
        final idx = enriched.indexWhere((g) => g.id == e.id);
        if (idx != -1) enriched[idx] = e;
      }

      // Start with enriched, optionally augment expansions from top match
      List<Game> augmented = List.from(enriched);
      if (rawResults.isNotEmpty) {
        try {
          final top = enriched.firstWhere((g) => g.id == rawResults.first.id, orElse: () => enriched.first);
          // If the top already has expansions from enrichment, use them; otherwise fetch again
          if (top.expansions.isEmpty) {
            final details = await _bgg.getGameDetails(top.id);
            if (details != null && details.expansions.isNotEmpty) {
              for (final exp in details.expansions) {
                if (!augmented.any((g) => g.id == exp.id)) {
                  augmented.add(Game(id: exp.id, name: exp.name, year: ''));
                }
              }
            }
          }
        } catch (_) {}
      }

      // Dedup against user collections + apply advanced filters
      final userIds = {..._myCollection.map((g) => g.id), ..._wishlist.map((g) => g.id)};
      final filtered = augmented
          .where((g) => !userIds.contains(g.id) && _matchesFilters(g))
          .toList();

      // Show first 25 (client-side page), but keep any extra from the larger fetch for potential immediate use.
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

        // Enrich modestly for this page to avoid rate limit issues
        final toEnrichMore = moreRaw.take(15).toList();
        final enrichedTopMore = await _enrichGames(toEnrichMore);

        final enrichedMore = List<Game>.from(moreRaw);
        for (final e in enrichedTopMore) {
          final idx = enrichedMore.indexWhere((g) => g.id == e.id);
          if (idx != -1) enrichedMore[idx] = e;
        }

        // Accept what BGG returned for the page (BGG already matched the query).
        // Only filter: not user-owned, not already in current results, and pass active filters.
        final newCandidates = enrichedMore.where((g) {
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
        _searchBggLibrary(cleaned); // live BGG (with filters for discovery if active)
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

    // No collection yet: do a live BGG search for a real random game (no hardcoded data)
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Picking a random game from BGG...')),
      );
    }

    try {
      final raw = await _bgg.searchGames('game', limit: 15);
      if (raw.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not fetch from BGG. Search the library and add some games first!')),
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
          const SnackBar(content: Text('Could not pick random game. Try searching the library instead.')),
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
                      Text('Minimum BGG Rating', style: Theme.of(context).textTheme.titleMedium),
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
          SnackBar(content: Text('Removed ${game.name} from My Collection')),
        );
      } else {
        _myCollection.add(game);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${game.name} to My Collection')),
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
          SnackBar(content: Text('Removed ${game.name} from Wishlist')),
        );
      } else {
        _wishlist.add(game);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${game.name} to Wishlist')),
        );
      }
    });
    _saveCollections();
  }

  void _showCollection() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('My Collection (Owned Games)', style: Theme.of(context).textTheme.headlineSmall),
            content: _myCollection.isEmpty
                ? const Text('No games yet. Scan or add manually, then choose "I Own This".')
                : ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Search inside collection
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
            title: Text('My Wishlist (Shopping)', style: Theme.of(context).textTheme.headlineSmall),
            content: _wishlist.isEmpty
                ? const Text('No games on wishlist yet. Scan interesting games and choose "Want to Buy".')
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

  void _logPlay(Game game) {
    DateTime selectedDate = DateTime.now();
    int players = game.minPlayers > 0 ? game.minPlayers : 2;
    double? rating;
    String notes = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text('Log Play for ${game.name}'),
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
                                  builder: (_) => GameDetailPage(game: selectedGame!),
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
                            child: const Text('Spin Again'),
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
      appBar: AppBar(
        title: const Text('Board Game Snap'),
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
                    'Identify board games from photos, search the catalog, and explore details.',
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Find your next board game',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Identify games while shopping or from your collection. Add to Wishlist or My Collection.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search games (BoardGameGeek library + yours)',
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
              // Optional advanced filters row
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
                      icon: const Icon(Icons.casino),
                      label: const Text('Random game'),
                      onPressed: _showRandomGame,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Fixed BGG header (stays above the scrollable list)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      'BoardGameGeek library',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_isSearchingBgg) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),

              Expanded(
                child: Builder(
                  builder: (context) {
                    if (_isSearchingBgg) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    } else if (_bggSearchResults.isEmpty) {
                      final hasQuery = _searchText.trim().length >= 2;
                      final String message;
                      final bool isFilterMode = _hasAnyFilter();

                      if (isFilterMode && !hasQuery) {
                        message = 'No games match your filters.\nTry broadening weight/rating/player ranges or add a search term.';
                      } else if (isFilterMode) {
                        message = 'No games match your search and filters.';
                      } else if (hasQuery) {
                        message = 'No BGG results. Try a different search term.';
                      } else {
                        message = 'Search above to explore BGG\'s full library (150k+ games).\n\nSet Filters (e.g. weight ~3, rating 7+) and search (even with little text) to discover matching games.';
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
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
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
                                      errorWidget: (c, u, e) => Icon(Icons.image, size: 50),
                                    ),
                                  )
                                : const Icon(Icons.videogame_asset, size: 50),
                            title: Text(
                              game.name,
                              style: theme.textTheme.titleMedium,
                            ),
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

              // Bottom actions in horizontal scroll to save vertical space and avoid overflow
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: _showWhatShouldWePlay,
                      icon: const Icon(Icons.casino_outlined),
                      label: const Text('What Should We Play?'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.purple,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _showCollection,
                      icon: const Icon(Icons.collections_bookmark),
                      label: Text('My Collection (${_myCollection.length})'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _showWishlist,
                      icon: const Icon(Icons.shopping_cart),
                      label: Text('Wishlist (${_wishlist.length})'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _showManualEntry,
                      icon: const Icon(Icons.edit),
                      label: const Text('Add manual entry'),
                    ),
                  ],
                ),
              ),
            ],
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

  const GameDetailPage({
    super.key,
    required this.game,
    this.isInMyCollection = false,
    this.isInWishlist = false,
    this.onAddToMyCollection,
    this.onAddToWishlist,
    this.onLogPlay,
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

          // Play History
          if (game.playCount > 0)
            _Section(
              title: 'Play History',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Plays: ${game.playCount}'),
                  if (game.lastPlayed != null)
                    Text('Last played: ${game.lastPlayed!.toLocal().toString().split(' ')[0]}'),
                  if (game.averageRating != null)
                    Text('Avg rating: ${game.averageRating!.toStringAsFixed(1)} / 10'),
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
            label: const Text('Log a Play'),
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
                  label: const Text('BGG Page'),
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
                                final fullExp = await BggService().getGameDetails(e.id);
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
                  title: const Text('BoardGameGeek Files'),
                  onTap: () {
                    final url = game.id.startsWith('manual_')
                        ? 'https://boardgamegeek.com/geeksearch.php?action=search&objecttype=boardgame&q=${Uri.encodeComponent(game.name)}'
                        : 'https://boardgamegeek.com/boardgame/${game.id}/files';
                    _launch(url, context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Full BGG Page'),
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

