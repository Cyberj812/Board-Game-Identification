import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

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

  final _picker = ImagePicker();
  final _ocr = OcrService();
  final _bgg = BggService();

  List<BoardGame> get _filteredGames {
    final query = _searchText.toLowerCase();
    if (query.isEmpty) {
      return sampleGames;
    }
    return sampleGames.where((game) {
      return game.name.toLowerCase().contains(query) ||
          game.publisher.toLowerCase().contains(query) ||
          game.description.toLowerCase().contains(query);
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
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GameDetailPage(game: fullGame),
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

  void _showRandomGame() {
    final game = (sampleGames..shuffle()).first;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SimpleGameDetail(game: game),
      ),
    );
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
                children: const [
                  Text('Browse games, search by name, and explore sample game details.'),
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
                              // Samples use simple detail for demo; scanned use rich
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => _SimpleGameDetail(game: game),
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
  final BoardGame game;
  final VoidCallback onTap;

  const GameCard({super.key, required this.game, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(game.name),
        subtitle: Text('${game.year} · ${game.publisher}'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class GameDetailPage extends StatelessWidget {
  final Game game;  // Now uses rich Game model from BGG

  const GameDetailPage({super.key, required this.game});

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
const sampleGames = <BoardGame>[
  BoardGame(
    name: 'Catan',
    year: 1995,
    publisher: 'Kosmos',
    description: 'Trade, build, and settle the island of Catan in this gateway strategy classic.',
  ),
  BoardGame(
    name: 'Ticket to Ride',
    year: 2004,
    publisher: 'Days of Wonder',
    description: 'Collect train cards, claim routes, and connect cities across the map.',
  ),
  BoardGame(
    name: 'Wingspan',
    year: 2019,
    publisher: 'Stonemaier Games',
    description: 'Build a wildlife preserve by attracting birds with different powers and habitats.',
  ),
  BoardGame(
    name: 'Pandemic',
    year: 2008,
    publisher: 'Z-Man Games',
    description: 'Work together to stop global outbreaks before time runs out.',
  ),
  BoardGame(
    name: 'Azul',
    year: 2017,
    publisher: 'Plan B Games',
    description: 'Draft tiles and complete patterns to score points in this elegant abstract game.',
  ),
];

// For compatibility with sample list (simple version)
class BoardGame {
  final String name;
  final int year;
  final String publisher;
  final String description;

  const BoardGame({
    required this.name,
    required this.year,
    required this.publisher,
    required this.description,
  });
}

class _SimpleGameDetail extends StatelessWidget {
  final BoardGame game;

  const _SimpleGameDetail({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(game.name)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(game.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${game.publisher} · ${game.year}'),
            const SizedBox(height: 16),
            Text(game.description, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
