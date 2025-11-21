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
