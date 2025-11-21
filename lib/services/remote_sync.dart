import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'local_db.dart';
import 'remote_sync_base.dart';

class RemoteSync implements RemoteSyncBase {
  final LocalDb localDb;
  final String updatesUrl;
  RemoteSync({required this.localDb, required this.updatesUrl});

  @override
  Future<int> sync() async {
    final res = await http.get(Uri.parse(updatesUrl));
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch updates.json (${res.statusCode})');
    }
    final List<dynamic> updates = jsonDecode(res.body);
    int applied = 0;

    for (final item in updates) {
      final song = Song.fromMap(item);
      await localDb.upsertSong(song);
      applied++;
    }
    return applied;
  }
}
