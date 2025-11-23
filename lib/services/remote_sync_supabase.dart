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
    // Paginate through the REST endpoint using limit/offset to avoid fetching
    // the entire table at once. This is more friendly for large datasets.
    const int pageSize = 100; // reasonable default page size
    int offset = 0;
    int applied = 0;
    // Respect the last successful sync time if available to perform an incremental sync.
    final DateTime? lastSynced = await localDb.getLastSynced();
    DateTime? maxUpdated;

    while (true) {
      final rows = await _fetchPage(offset: offset, limit: pageSize, retries: 3, since: lastSynced);
      if (rows.isEmpty) break;

      for (final row in rows) {
        try {
          final song = Song.fromMap(Map<String, dynamic>.from(row as Map));
          await localDb.upsertSong(song);
          // Track the newest updated_at we've seen so we can persist an accurate watermark
          if (maxUpdated == null || song.updatedAt.isAfter(maxUpdated)) {
            maxUpdated = song.updatedAt;
          }
          applied++;
        } catch (e) {
          // Resilient: log and continue with other rows instead of failing the whole sync
          // The caller (SongsNotifier) will get a non-fatal sync message if desired.
        }
      }

      if (rows.length < pageSize) break; // last page
      offset += pageSize;
    }

    // Persist last successful sync time so subsequent syncs can be incremental.
    try {
      final toPersist = maxUpdated?.toUtc() ?? DateTime.now().toUtc();
      await localDb.setLastSynced(toPersist);
    } catch (_) {
      // don't fail the sync if persisting the timestamp fails
    }
    return applied;
  }

  /// Internal helper to fetch a single page with retries.
  Future<List<dynamic>> _fetchPage({required int offset, required int limit, int retries = 1, DateTime? since}) async {
    // Build query string and optionally filter by updated_at > since
    var q = 'select=*&order=updated_at.asc&limit=$limit&offset=$offset';
    if (since != null) {
      final iso = Uri.encodeComponent(since.toUtc().toIso8601String());
      q += '&updated_at=gt.$iso';
    }
    final uri = Uri.parse('$supabaseUrl/rest/v1/songs?$q');
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        final res = await http.get(uri, headers: {
          'apikey': anonKey,
          'Authorization': 'Bearer $anonKey',
          'Prefer': 'return=representation'
        });

        if (res.statusCode >= 200 && res.statusCode < 300) {
          final List<dynamic> rows = jsonDecode(res.body) as List<dynamic>;
          return rows;
        }

        // non-success status code
        if (attempt >= retries) {
          throw Exception('Supabase REST query failed: ${res.statusCode} ${res.reasonPhrase} ${res.body}');
        }
      } catch (e) {
        if (attempt >= retries) rethrow;
        // backoff before retrying
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
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
    // Do not send `created_by` by default because some DBs may not have this column.
    // Ownership is tracked locally via `createdBy`. If you want server-side
    // ownership, add a `created_by` text column in your `songs` table and
    // re-enable sending this field.
    // Font size is optional and not sent to Supabase by default because many
    // projects don't include a `font_size` column. The app still persists
    // font size locally. If you want font sizes in the DB, add the column
    // and re-enable sending it here.

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

  /// Push only the font size for a song (upsert id + font_size)
  @override
  Future<void> pushFontSize(int id, double fontSize) async {
    if (supabaseUrl.isEmpty || anonKey.isEmpty) {
      throw Exception('Supabase not configured (empty URL or anon key)');
    }
    final payload = {'id': id, 'font_size': fontSize};
    final uri = Uri.parse('$supabaseUrl/rest/v1/songs?on_conflict=id');
    final res = await http.post(uri, headers: {
      'apikey': anonKey,
      'Authorization': 'Bearer $anonKey',
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates,return=representation',
    }, body: jsonEncode([payload]));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Supabase pushFontSize failed: ${res.statusCode} ${res.reasonPhrase} ${res.body}');
    }
  }
}
