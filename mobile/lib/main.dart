import 'package:flutter/material.dart';

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

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Scanning and OCR features are coming soon!'),
      ),
    );
  }

  void _showRandomGame() {
    final game = (sampleGames..shuffle()).first;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameDetailPage(game: game),
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
                      label: const Text('Scan game box'),
                      onPressed: _showComingSoon,
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
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => GameDetailPage(game: game),
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
  final BoardGame game;

  const GameDetailPage({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(game.name),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              game.name,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('${game.publisher} · ${game.year}'),
            const SizedBox(height: 16),
            Text(game.description, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.info_outline),
              label: const Text('Learn more'),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Game detail pages are a starting point.')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

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
