import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _searchText = '';
  bool _isScanning = false;
  List<Game> _userCollection = []; // For custom lists and manual entries
  bool _buildCollectionMode = false; // Toggle for collection photo building

  final _picker = ImagePicker();
  final _ocr = OcrService();
  final _bgg = BggService();

  @override
  void initState() {
    super.initState();
    _loadCollection();
  }

  Future<void> _loadCollection() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('userCollection') ?? [];
    setState(() {
      _userCollection = jsonList
          .map((jsonStr) => Game.fromJson(jsonDecode(jsonStr)))
          .toList();
    });
  }

  Future<void> _saveCollection() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _userCollection.map((g) => jsonEncode(g.toJson())).toList();
    await prefs.setStringList('userCollection', jsonList);
  }

  List<Game> get _filteredGames {
    final query = _searchText.toLowerCase();
    if (query.isEmpty) {
      return sampleGames;
    }
    return sampleGames.where((game) {
      return game.name.toLowerCase().contains(query) ||
          (game.description ?? '').toLowerCase().contains(query);
    }).toList();
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read text from image. Try better lighting.')),
          );
        }
        return;
      }

      // Search BGG using extracted text
      final results = await _bgg.searchGames(text, limit: 5);

      if (results.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No matching games found. Try another photo.')),
          );
        }
        return;
      }

      // Fetch details for the top match
      final top = results.first;
      final fullGame = await _bgg.getGameDetails(top.id);

      if (fullGame != null && mounted) {
        _addToCollection(fullGame); // Always add to collection for photo building
        if (!_buildCollectionMode) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GameDetailPage(
                game: fullGame,
                onAddToCollection: () => _addToCollection(fullGame),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${fullGame.name} added to collection from photo')),
          );
        }
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

  void _showRandomGame() {
    final game = (sampleGames..shuffle()).first;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameDetailPage(
          game: game,
          onAddToCollection: () => _addToCollection(game),
        ),
      ),
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

  void _addToCollection(Game game) {
    setState(() {
      if (!_userCollection.any((g) => g.id == game.id)) {
        _userCollection.add(game);
      }
    });
    _saveCollection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${game.name} added to My Collection')),
    );
  }

  void _showCollection() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('My Collection'),
            content: _userCollection.isEmpty
                ? const Text('No games in collection yet. Scan (in Build Mode) or add manually!')
                : SizedBox(
                    width: double.maxFinite,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListView.builder(
                          shrinkWrap: true,
                          itemCount: _userCollection.length,
                          itemBuilder: (c, i) {
                            final g = _userCollection[i];
                            return ListTile(
                              title: Text(g.name),
                              subtitle: Text(g.year),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () {
                                  setState(() {
                                    _userCollection.removeAt(i);
                                  });
                                  setDialogState(() {});
                                  _saveCollection();
                                },
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => GameDetailPage(
                                      game: g,
                                      onAddToCollection: () => _addToCollection(g),
                                    ),
                                  ),
                                );
                              },
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
                                setState(() => _buildCollectionMode = true);
                                _scanBox(); // Directly start scan for collection
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
              if (_userCollection.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() => _userCollection.clear());
                    setDialogState(() {});
                    _saveCollection();
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
                _addToCollection(manual);
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Find your next board game',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Search the sample catalog or tap a game card to see details.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search games',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchText = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.camera_alt),
                      label: _isScanning ? const Text('Scanning...') : const Text('Scan game box'),
                      onPressed: _isScanning ? null : _scanBox,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.casino),
                      label: const Text('Random game'),
                      onPressed: _showRandomGame,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _showManualEntry,
                  icon: const Icon(Icons.edit),
                  label: const Text('Add manual entry'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _showIllegalMoveChecker,
                  icon: const Icon(Icons.gavel),
                  label: const Text('Illegal Move Checker (photo game state)'),
                  style: TextButton.styleFrom(foregroundColor: Colors.orange),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _openFeedback,
                  icon: const Icon(Icons.feedback_outlined, size: 18),
                  label: const Text('Report a bug or suggest improvement'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: OutlinedButton.icon(
                  onPressed: _showCollection,
                  icon: const Icon(Icons.list),
                  label: Text('My Collection (${_userCollection.length})'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Build Collection Mode'),
                  Switch(
                    value: _buildCollectionMode,
                    onChanged: (val) => setState(() => _buildCollectionMode = val),
                  ),
                  const Text('(photo of collection)'),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _filteredGames.isEmpty
                    ? const Center(
                        child: Text(
                          'No games found. Try a different search term.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        itemCount: _filteredGames.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final game = _filteredGames[index];
                          return GameCard(
                            game: game,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => GameDetailPage(
                                    game: game,
                                    onAddToCollection: () => _addToCollection(game),
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
        ),
      ),
    );
  }
}

class GameCard extends StatelessWidget {
  final Game game;
  final VoidCallback onTap;

  const GameCard({super.key, required this.game, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(game.name),
        subtitle: Text('${game.year} · ${game.description ?? "Board Game"}'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class GameDetailPage extends StatelessWidget {
  final Game game;  // Now uses rich Game model from BGG
  final VoidCallback? onAddToCollection;

  const GameDetailPage({super.key, required this.game, this.onAddToCollection});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(game.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(game.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(game.year),
          const SizedBox(height: 16),

          // Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatItem(label: 'Players', value: game.playerCount),
              _StatItem(label: 'Weight', value: game.weightString),
              _StatItem(label: 'Rank', value: game.rankString),
              _StatItem(label: 'Time', value: game.playtime.isNotEmpty ? '${game.playtime} min' : '?'),
            ],
          ),

          const SizedBox(height: 24),

          // Add to Collection button
          ElevatedButton.icon(
            onPressed: () {
              if (onAddToCollection != null) {
                onAddToCollection!();
              } else {
                // Fallback for direct navigation
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${game.name} would be added to collection')),
                );
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Add to My Collection'),
          ),

          const SizedBox(height: 16),

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
                    onTap: platform.url != null ? () => _launch(platform.url!) : null,
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
                        .map((e) => ListTile(dense: true, title: Text(e.name)))
                        .toList(),
                  ),
          ),

          // How to Play Videos
          _Section(
            title: 'How to Play Videos',
            child: Column(
              children: _buildVideoLinks(game.name).map((link) {
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(link.$1),
                  onTap: () => _launch(link.$2),
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
                  onTap: () => _launch('https://boardgamegeek.com/boardgame/${game.id}/files'),
                ),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Full BGG Page'),
                  onTap: () => _launch('https://boardgamegeek.com/boardgame/${game.id}'),
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
      ('Watch It Played', 'https://www.youtube.com/results?search_query=how+to+play+$slug+%22watch+it+played%22'),
      ('Rules Explained', 'https://www.youtube.com/results?search_query=$slug+rules+explained'),
      ('Search YouTube', 'https://www.youtube.com/results?search_query=how+to+play+$slug'),
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

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
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

// Simple demo data for browse (limited info)
final sampleGames = <Game>[
  Game(
    id: 'sample_catan',
    name: 'Catan',
    year: '1995',
    description: 'Trade, build, and settle the island of Catan in this gateway strategy classic.',
  ),
  Game(
    id: 'sample_ticket',
    name: 'Ticket to Ride',
    year: '2004',
    description: 'Collect train cards, claim routes, and connect cities across the map.',
  ),
  Game(
    id: 'sample_wingspan',
    name: 'Wingspan',
    year: '2019',
    description: 'Build a wildlife preserve by attracting birds with different powers and habitats.',
  ),
  Game(
    id: 'sample_pandemic',
    name: 'Pandemic',
    year: '2008',
    description: 'Work together to stop global outbreaks before time runs out.',
  ),
  Game(
    id: 'sample_azul',
    name: 'Azul',
    year: '2017',
    description: 'Draft tiles and complete patterns to score points in this elegant abstract game.',
  ),
];

