import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Push `songs.json` to Supabase REST.
///
/// Usage:
///  - Local file (default): `dart run tool/push_songs_to_supabase.dart`
///  - Remote URL: `dart run tool/push_songs_to_supabase.dart https://raw.githubusercontent.com/owner/repo/branch/path/songs.json`
///
/// Behavior:
///  - Reads `SUPABASE_URL` and optional `SUPABASE_ANON_KEY` from `lib/config.dart`.
///  - Prefers `SUPABASE_SERVICE_ROLE` environment variable when present (for admin writes).
///  - Sanitizes each song and upserts to `/rest/v1/songs?on_conflict=id`.
Future<void> main(List<String> args) async {
  final configFile = File('lib/config.dart');
  String supabaseUrl = '';
  String anonKeyFromConfig = '';

  if (await configFile.exists()) {
    final config = await configFile.readAsString();
    final urlMatch = RegExp(r"SUPABASE_URL\s*=\s*'([^']*)'").firstMatch(config);
    final keyMatch = RegExp(r"SUPABASE_ANON_KEY\s*=\s*'([^']*)'").firstMatch(config);
    supabaseUrl = urlMatch?.group(1) ?? '';
    anonKeyFromConfig = keyMatch?.group(1) ?? '';
  }

  final serviceRole = Platform.environment['SUPABASE_SERVICE_ROLE'] ?? '';
  final supabaseKey = serviceRole.isNotEmpty ? serviceRole : anonKeyFromConfig;

  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    stderr.writeln('Supabase URL or API key not found. Put SUPABASE_URL in lib/config.dart and/or set SUPABASE_SERVICE_ROLE env var.');
    exit(2);
  }

  // Load JSON: remote URL (args[0]) or local assets/songs.json
  String rawJson;
  if (args.isNotEmpty && args[0].startsWith('http')) {
    final uri = Uri.parse(args[0]);
    stdout.writeln('Fetching remote JSON: ${uri}');
    final r = await http.get(uri);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      stderr.writeln('Failed to fetch remote JSON: ${r.statusCode} ${r.reasonPhrase}');
      exit(2);
    }
    rawJson = r.body;
  } else {
    final songsFile = File('assets/songs.json');
    if (!await songsFile.exists()) {
      stderr.writeln('assets/songs.json not found and no remote URL supplied');
      exit(2);
    }
    rawJson = await songsFile.readAsString();
  }

  final dynamic parsed = jsonDecode(rawJson);
  if (parsed is! List) {
    stderr.writeln('JSON does not contain an array of songs');
    exit(2);
  }

  final List<Map<String, dynamic>> payload = [];
  for (final item in parsed) {
    if (item is Map<String, dynamic>) {
      final map = Map<String, dynamic>.from(item);

      // Normalize fields; ensure updated_at exists
      final updatedAt = map['updatedAt'] ?? map['updated_at'] ?? DateTime.now().toIso8601String();
      final favorite = map['favorite'] ?? false;

      final sanitized = <String, dynamic>{
        if (map.containsKey('id')) 'id': map['id'],
        'title': map['title'],
        'lyrics': map['lyrics'],
        'language': map['language'],
        'category': map['category'],
        'updated_at': updatedAt,
        'favorite': favorite,
      };

      // If font size present, send as snake_case `font_size` (update DB schema accordingly)
      if (map.containsKey('fontSize')) {
        sanitized['font_size'] = map['fontSize'];
      } else if (map.containsKey('font_size')) {
        sanitized['font_size'] = map['font_size'];
      }

      payload.add(sanitized);
    }
  }

  final uri = Uri.parse('$supabaseUrl/rest/v1/songs?on_conflict=id');
  final headers = {
    'apikey': supabaseKey,
    'Authorization': 'Bearer $supabaseKey',
    'Content-Type': 'application/json',
    'Prefer': 'resolution=merge-duplicates,return=representation',
  };

  stdout.writeln('Pushing ${payload.length} songs to Supabase at $uri');
  final res = await http.post(uri, headers: headers, body: jsonEncode(payload));

  if (res.statusCode >= 200 && res.statusCode < 300) {
    stdout.writeln('Success: ${res.statusCode}');
    stdout.writeln(res.body);
    return;
  }

  stderr.writeln('Failed: ${res.statusCode} ${res.reasonPhrase}');
  stderr.writeln(res.body);
  exit(3);
}
