class Game {
  final String id;
  final String name;
  final String year;
  final int minPlayers;
  final int maxPlayers;
  final String playtime;
  final String minAge;
  final double? weight;
  final int? rank;
  final double? rating; // BGG community average rating (1-10)
  final String? imageUrl;
  final String? description; // For manual and samples
  final List<String> categories;
  final List<String> mechanics;
  final List<Expansion> expansions;
  final List<DigitalPlatform> digitalPlatforms; // Digital availability
  List<PlayLog> playLogs; // For play logging & stats

  Game({
    required this.id,
    required this.name,
    this.year = '',
    this.minPlayers = 0,
    this.maxPlayers = 0,
    this.playtime = '',
    this.minAge = '',
    this.weight,
    this.rank,
    this.rating,
    this.imageUrl,
    this.description,
    this.categories = const [],
    this.mechanics = const [],
    this.expansions = const [],
    this.digitalPlatforms = const [],
    List<PlayLog>? playLogs,
  }) : playLogs = playLogs ?? [];

  void addPlay(PlayLog log) {
    playLogs.add(log);
  }

  int get playCount => playLogs.length;

  DateTime? get lastPlayed => playLogs.isNotEmpty 
      ? playLogs.map((p) => p.date).reduce((a, b) => a.isAfter(b) ? a : b) 
      : null;

  double? get averageRating {
    if (playLogs.isEmpty) return null;
    final rated = playLogs.where((p) => p.rating != null).map((p) => p.rating!);
    if (rated.isEmpty) return null;
    return rated.reduce((a, b) => a + b) / rated.length;
  }

  String get playerCount {
    if (minPlayers == 0 && maxPlayers == 0) return '?';
    if (minPlayers == maxPlayers) return '$minPlayers';
    return '$minPlayers–$maxPlayers';
  }

  String get weightString => weight != null ? '${weight!.toStringAsFixed(1)}/5' : '?';
  String get rankString => rank != null ? '#$rank' : 'Unranked';
  String get ratingString => rating != null ? rating!.toStringAsFixed(1) : 'Unrated';

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown',
      year: json['year'] ?? '',
      minPlayers: json['min_players'] ?? 0,
      maxPlayers: json['max_players'] ?? 0,
      playtime: json['playtime'] ?? '',
      minAge: json['min_age'] ?? '',
      weight: (json['weight'] as num?)?.toDouble(),
      rank: json['rank'] as int?,
      rating: (json['rating'] as num?)?.toDouble(),
      imageUrl: json['image'],
      description: json['description'],
      categories: List<String>.from(json['categories'] ?? []),
      mechanics: List<String>.from(json['mechanics'] ?? []),
      expansions: (json['expansions'] as List? ?? [])
          .map((e) => Expansion.fromJson(e))
          .toList(),
      digitalPlatforms: (json['digital_platforms'] as List? ?? [])
          .map((d) => DigitalPlatform.fromJson(d))
          .toList(),
      playLogs: (json['play_logs'] as List? ?? [])
          .map((p) => PlayLog.fromJson(p))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'year': year,
        'min_players': minPlayers,
        'max_players': maxPlayers,
        'playtime': playtime,
        'min_age': minAge,
        'weight': weight,
        'rank': rank,
        'rating': rating,
        'image': imageUrl,
        'description': description,
        'categories': categories,
        'mechanics': mechanics,
        'expansions': expansions.map((e) => e.toJson()).toList(),
        'digital_platforms': digitalPlatforms.map((d) => d.toJson()).toList(),
        'play_logs': playLogs.map((p) => p.toJson()).toList(),
      };
}

class Expansion {
  final String id;
  final String name;

  Expansion({required this.id, required this.name});

  factory Expansion.fromJson(Map<String, dynamic> json) =>
      Expansion(id: json['id'], name: json['name']);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class DigitalPlatform {
  final String name; // e.g. "Board Game Arena", "Tabletop Simulator", "Steam"
  final String? url;  // Optional link

  DigitalPlatform({required this.name, this.url});

  factory DigitalPlatform.fromJson(Map<String, dynamic> json) =>
      DigitalPlatform(name: json['name'], url: json['url']);

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
      };
}

class PlayLog {
  final DateTime date;
  final int players;
  final double? rating; // 1-10
  final String? notes;

  PlayLog({
    required this.date,
    required this.players,
    this.rating,
    this.notes,
  });

  factory PlayLog.fromJson(Map<String, dynamic> json) => PlayLog(
        date: DateTime.parse(json['date']),
        players: json['players'],
        rating: json['rating']?.toDouble(),
        notes: json['notes'],
      );

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'players': players,
        'rating': rating,
        'notes': notes,
      };
}
