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
}
