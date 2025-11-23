import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
// import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/song.dart';

class LocalDb {
  static const String songsBoxName = 'songsBox';
  static const String settingsBoxName = 'settingsBox';

  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox<Map>(songsBoxName);
    // open a small settings box for UI preferences
    await Hive.openBox(settingsBoxName);
  }

  Future<void> _ensureInitialized() async {
    if (!Hive.isBoxOpen(songsBoxName) || !Hive.isBoxOpen(settingsBoxName)) {
      await init();
    }
  }

  Future<void> seedFromAssetsIfEmpty() async {
    final box = Hive.box<Map>(songsBoxName);
    if (box.isEmpty) {
      final jsonStr = await rootBundle.loadString('assets/songs.json');
      final List<dynamic> data = jsonDecode(jsonStr);
      for (final item in data) {
        final song = Song.fromMap(item);
        await box.put(song.id, song.toMap());
      }
    }
  }

  Future<void> setLastSelectedCategory(String? category) async {
    await _ensureInitialized();
    final box = Hive.box(settingsBoxName);
    await box.put('lastCategory', category);
  }

  Future<String?> getLastSelectedCategory() async {
    await _ensureInitialized();
    final box = Hive.box(settingsBoxName);
    final v = box.get('lastCategory');
    if (v == null) return null;
    return v.toString();
  }

  /// Persist the last successful remote sync time (UTC ISO string) in settings.
  Future<void> setLastSynced(DateTime? when) async {
    await _ensureInitialized();
    final box = Hive.box(settingsBoxName);
    if (when == null) {
      await box.delete('lastSynced');
    } else {
      await box.put('lastSynced', when.toUtc().toIso8601String());
    }
  }

  /// Read the last successful remote sync time from settings.
  Future<DateTime?> getLastSynced() async {
    await _ensureInitialized();
    final box = Hive.box(settingsBoxName);
    final v = box.get('lastSynced');
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  /// Returns a stable local user id stored in settings. If absent, generates and stores one.
  Future<String> getLocalUserId() async {
    await _ensureInitialized();
    final box = Hive.box(settingsBoxName);
    final key = 'local_user_id';
    var v = box.get(key);
    if (v != null) return v.toString();
    final newId = _generateLocalUserId();
    await box.put(key, newId);
    return newId;
  }
  
  Future<List<int>> getSongOrder() async {
    await _ensureInitialized();
    final box = Hive.box(settingsBoxName);
    final v = box.get('songOrder');
    if (v == null) return [];
    return List<int>.from(v);
  }
  
  Future<void> saveSongOrder(List<int> ids) async {
    await _ensureInitialized();
    final box = Hive.box(settingsBoxName);
    await box.put('songOrder', ids);
  }

  String _generateLocalUserId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rnd = DateTime.now().microsecondsSinceEpoch % 1000000;
    return 'local_${now.toRadixString(36)}_${rnd.toRadixString(36)}';
  }

  Future<List<Song>> getAll() async {
    await _ensureInitialized();
    final box = Hive.box<Map>(songsBoxName);
    return box.values.map((e) => Song.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> upsertSong(Song song) async {
    await _ensureInitialized();
    final box = Hive.box<Map>(songsBoxName);
    await box.put(song.id, song.toMap());
  }

  Future<void> setFavorite(int id, bool value) async {
    await _ensureInitialized();
    final box = Hive.box<Map>(songsBoxName);
    final m = box.get(id);
    if (m == null) return;
    final map = Map<String, dynamic>.from(m);
    map['favorite'] = value;
    await box.put(id, map);
  }

  Future<List<Song>> getFavorites() async {
    final all = await getAll();
    return all.where((s) => s.favorite).toList();
  }

  Future<void> deleteSong(int id) async {
    final box = Hive.box<Map>(songsBoxName);
    await box.delete(id);
  }

  Future<List<Song>> searchByTitle(String query) async {
    final q = query.toLowerCase().trim();
    final all = await getAll();
    return all.where((s) => s.title.toLowerCase().contains(q)).toList();
  }

  Future<List<Song>> filterByCategory(String category) async {
    final all = await getAll();
    return all.where((s) => s.category == category).toList();
  }
}
