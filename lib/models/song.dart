class Song {
  final int id;
  final String title;
  final String lyrics;
  final String language;
  final String category;
  final DateTime updatedAt;
  final bool favorite;
  final double? fontSize;

  Song({
    required this.id,
    required this.title,
    required this.lyrics,
    required this.language,
    required this.category,
    required this.updatedAt,
    this.fontSize,
    this.favorite = false,
  });

  factory Song.fromMap(Map<String, dynamic> map) {
    return Song(
      id: map['id'] is String ? int.parse(map['id']) : map['id'],
      title: map['title'],
      lyrics: map['lyrics'],
      language: map['language'],
      category: map['category'],
      updatedAt: DateTime.parse(map['updatedAt']),
      fontSize: map.containsKey('fontSize') && map['fontSize'] != null
          ? (map['fontSize'] is num ? (map['fontSize'] as num).toDouble() : double.parse(map['fontSize'].toString()))
          : null,
      favorite: map.containsKey('favorite')
          ? (map['favorite'] is bool ? map['favorite'] : map['favorite'].toString().toLowerCase() == 'true')
          : false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'lyrics': lyrics,
      'language': language,
      'category': category,
      'updatedAt': updatedAt.toIso8601String(),
      if (fontSize != null) 'fontSize': fontSize,
      'favorite': favorite,
    };
  }
}
