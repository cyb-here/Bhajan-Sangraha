import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'local_db.dart';
import 'remote_sync_base.dart';

class RemoteSyncSupabase implements RemoteSyncBase {
  final LocalDb localDb;
  final String supabaseUrl;
  final String anonKey;

  RemoteSyncSupabase({required this.localDb, required this.supabaseUrl, required this.anonKey});

  /// Fetch all rows from the `songs` table via Supabase REST and upsert into local Hive.
  /// Returns the number of applied rows.
  @override
  Future<int> sync() async {
    if (supabaseUrl.isEmpty || anonKey.isEmpty) {
      throw Exception('Supabase not configured (empty URL or anon key)');
    }
    final uri = Uri.parse('$supabaseUrl/rest/v1/songs?select=*');
    final res = await http.get(uri, headers: {
      'apikey': anonKey,
      'Authorization': 'Bearer $anonKey',
      'Prefer': 'return=representation'
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Supabase REST query failed: ${res.statusCode} ${res.reasonPhrase}');
    }
    final List<dynamic> rows = jsonDecode(res.body) as List<dynamic>;
    int applied = 0;
    for (final row in rows) {
      final song = Song.fromMap(Map<String, dynamic>.from(row as Map));
      await localDb.upsertSong(song);
      applied++;
    }
    return applied;
  }

  /// Upsert a single song into Supabase `songs` table.
  @override
  Future<void> pushSong(dynamic song) async {
    if (supabaseUrl.isEmpty || anonKey.isEmpty) {
      throw Exception('Supabase not configured (empty URL or anon key)');
    }
    final Map<String, dynamic> map = song is Map<String, dynamic> ? song : song.toMap();
    // ensure snake_case keys for backend
    final payload = {
      if (map.containsKey('id')) 'id': map['id'],
      'title': map['title'],
      'lyrics': map['lyrics'],
      'language': map['language'],
      'category': map['category'],
      'updated_at': map['updatedAt'] ?? map['updated_at'] ?? DateTime.now().toIso8601String(),
      'favorite': map['favorite'] ?? false,
    };
    if (map.containsKey('fontSize')) payload['font_size'] = map['fontSize'];

    final uri = Uri.parse('$supabaseUrl/rest/v1/songs?on_conflict=id');
    final res = await http.post(uri, headers: {
      'apikey': anonKey,
      'Authorization': 'Bearer $anonKey',
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates,return=representation',
    }, body: jsonEncode([payload]));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Supabase push failed: ${res.statusCode} ${res.reasonPhrase} ${res.body}');
    }
  }

  /// Delete a song by id in Supabase
  @override
  Future<void> deleteSong(int id) async {
    if (supabaseUrl.isEmpty || anonKey.isEmpty) {
      throw Exception('Supabase not configured (empty URL or anon key)');
    }
    final uri = Uri.parse('$supabaseUrl/rest/v1/songs?id=eq.$id');
    final res = await http.delete(uri, headers: {
      'apikey': anonKey,
      'Authorization': 'Bearer $anonKey',
      'Content-Type': 'application/json',
    });
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Supabase delete failed: ${res.statusCode} ${res.reasonPhrase} ${res.body}');
    }
  }
}
