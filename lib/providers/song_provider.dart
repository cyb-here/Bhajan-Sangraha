import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/local_db.dart';
import '../services/remote_sync.dart';

/// Provider for the local Hive database service
final localDbProvider = Provider<LocalDb>((ref) => LocalDb());

/// Provider for the remote updates URL (GitHub Pages JSON)
final updatesUrlProvider = Provider<String>((ref) =>
    'https://cyb-here.github.io/Lyrics-App-Data/update.json'); // replace with your actual URL

/// Provider for the remote sync service
final remoteSyncProvider = Provider<RemoteSync>((ref) =>
    RemoteSync(localDb: ref.read(localDbProvider), updatesUrl: ref.read(updatesUrlProvider)));

/// StateNotifierProvider that manages the list of songs
final songsProvider =
    StateNotifierProvider<SongsNotifier, AsyncValue<List<Song>>>((ref) {
  return SongsNotifier(ref);
});

/// Provider to surface short sync status messages to the UI (snackbars)
final syncMessageProvider = StateProvider<String?>((ref) => null);

/// Provider for the app's ThemeMode (light/dark)
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

class SongsNotifier extends StateNotifier<AsyncValue<List<Song>>> {
  final Ref ref;

  SongsNotifier(this.ref) : super(const AsyncValue.loading()) {
    _init(); // private init on first load
  }

  /// Initialize local DB and seed from assets if empty
  Future<void> _init() async {
    final db = ref.read(localDbProvider);
    await db.init();
    await db.seedFromAssetsIfEmpty();
    final songs = await db.getAll();
    state = AsyncValue.data(songs);
    // attempt a remote sync on app startup (refreshFromRemote will surface messages)
    try {
      await refreshFromRemote();
    } catch (_) {
      // message already set by refreshFromRemote
    }
  }

  /// Public wrapper to reload all songs from Hive
  Future<void> reloadAll() async {
    final songs = await ref.read(localDbProvider).getAll();
    state = AsyncValue.data(songs);
  }

  /// Refresh songs from remote JSON (GitHub Pages)
  /// Refresh songs from remote JSON (GitHub Pages)
  /// Returns the number of applied updates.
  Future<int> refreshFromRemote() async {
    try {
      final sync = ref.read(remoteSyncProvider);
      final applied = await sync.sync();
      final songs = await ref.read(localDbProvider).getAll();
      state = AsyncValue.data(songs);
      // surface a short message for UI listeners (manual or startup sync)
      ref.read(syncMessageProvider.notifier).state = 'Sync completed: $applied updates';
      return applied;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      ref.read(syncMessageProvider.notifier).state = 'Sync failed: ${e.toString()}';
      rethrow;
    }
  }

  /// Always reload from Hive when searching
  Future<void> search(String query) async {
    final all = await ref.read(localDbProvider).getAll();
    final results = all
        .where((s) => s.title.toLowerCase().contains(query.toLowerCase()))
        .toList();
    state = AsyncValue.data(results);
  }

  /// Always reload from Hive when filtering
  Future<void> filterByCategory(String category) async {
    final all = await ref.read(localDbProvider).getAll();
    final results = all.where((s) => s.category == category).toList();
    state = AsyncValue.data(results);
  }

  /// Toggle favorite state for a song and return the updated Song
  Future<Song?> toggleFavorite(int id, [bool? setValue]) async {
    final db = ref.read(localDbProvider);
    final all = await db.getAll();
    final idx = all.indexWhere((s) => s.id == id);
    if (idx == -1) return null;
    final s = all[idx];
    final newVal = setValue ?? !s.favorite;
    final updated = Song(
      id: s.id,
      title: s.title,
      lyrics: s.lyrics,
      language: s.language,
      category: s.category,
      updatedAt: s.updatedAt,
      fontSize: s.fontSize,
      favorite: newVal,
    );
    await db.upsertSong(updated);
    // Update the current in-memory state to avoid clearing any active category filter
    final current = state;
    if (current is AsyncData<List<Song>>) {
      final list = current.value;
      final newList = list.map((x) => x.id == id ? updated : x).toList();
      state = AsyncValue.data(newList);
    } else {
      // fallback: reload everything from DB
      await reloadAll();
    }
    return updated;
  }
}
