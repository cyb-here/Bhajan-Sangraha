class Song {
  final int id;
  final String title;
  final String lyrics;
  final String language;
  final String category;
  final DateTime updatedAt;
  final bool favorite;
  final double? fontSize;
  final String? createdBy;

  Song({
    required this.id,
    required this.title,
    required this.lyrics,
    required this.language,
    required this.category,
    required this.updatedAt,
    this.fontSize,
    this.favorite = false,
    this.createdBy,
  });

  factory Song.fromMap(Map<String, dynamic> map) {
    // Accept both camelCase and snake_case keys coming from different sources
    final dynamic rawId = map['id'] ?? map['Id'];
    final id = rawId is String ? int.tryParse(rawId) ?? 0 : (rawId ?? 0);

    final title = (map['title'] ?? map['Title'] ?? '')?.toString();
    final lyrics = (map['lyrics'] ?? map['Lyrics'] ?? '')?.toString();
    final language = (map['language'] ?? map['lang'] ?? '')?.toString();
    final category = (map['category'] ?? map['Category'] ?? '')?.toString();

    // updatedAt might come as `updatedAt` or `updated_at` or be absent
    final updatedRaw = map['updatedAt'] ?? map['updated_at'] ?? map['updatedat'] ?? map['updatedAt'];
    DateTime updatedAt;
    try {
      if (updatedRaw == null) {
        updatedAt = DateTime.now();
      } else if (updatedRaw is DateTime) {
        updatedAt = updatedRaw;
      } else {
        updatedAt = DateTime.parse(updatedRaw.toString());
      }
    } catch (_) {
      updatedAt = DateTime.now();
    }

    double? fontSize;
    final fs = map['fontSize'] ?? map['font_size'] ?? map['fontsize'];
    if (fs != null) {
      if (fs is num) fontSize = fs.toDouble();
      else {
        final parsed = double.tryParse(fs.toString());
        if (parsed != null) fontSize = parsed;
      }
    }

    final favRaw = map['favorite'] ?? map['is_favorite'] ?? map['fav'] ?? false;
    final favorite = favRaw is bool ? favRaw : favRaw.toString().toLowerCase() == 'true';

    final createdBy = (map['createdBy'] ?? map['created_by'] ?? map['creator'])?.toString();

    return Song(
      id: id is int ? id : (id as int),
      title: title ?? '',
      lyrics: lyrics ?? '',
      language: language ?? '',
      category: category ?? '',
      updatedAt: updatedAt,
      fontSize: fontSize,
      favorite: favorite,
      createdBy: createdBy,
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
      if (createdBy != null) 'createdBy': createdBy,
    };
  }
}
