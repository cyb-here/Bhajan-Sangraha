import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/local_db.dart';
import '../services/remote_sync.dart';
import '../services/remote_sync_base.dart';
import '../services/remote_sync_supabase.dart';
import '../config.dart';

/// Provider for the local Hive database service
final localDbProvider = Provider<LocalDb>((ref) => LocalDb());

/// Provider for the remote updates URL (GitHub Pages JSON)
final updatesUrlProvider = Provider<String>((ref) =>
    'https://cyb-here.github.io/Lyrics-App-Data/update.json'); // replace with your actual URL

/// Provider for the remote sync service
final remoteSyncProvider = Provider<RemoteSyncBase>((ref) {
  // If Supabase config is provided, use Supabase-backed sync; otherwise fall back to JSON remote.
  if (SUPABASE_URL.isNotEmpty && SUPABASE_ANON_KEY.isNotEmpty) {
    final db = ref.read(localDbProvider);
    return RemoteSyncSupabase(localDb: db, supabaseUrl: SUPABASE_URL, anonKey: SUPABASE_ANON_KEY);
  }
  return RemoteSync(localDb: ref.read(localDbProvider), updatesUrl: ref.read(updatesUrlProvider));
});

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
      // Do not replace the in-memory `state` here — let the UI reapply its
      // active filter (or call reloadAll) after the sync finishes. Replacing
      // `state` with the full list causes a brief flash where the UI shows
      // all songs before category filters are reapplied.
      // surface a short message for UI listeners (manual or startup sync)
      final source = sync is RemoteSyncSupabase ? 'Supabase' : 'Remote';
      ref.read(syncMessageProvider.notifier).state = '$source sync completed: $applied updates';
      return applied;
    } catch (e) {
      // Keep the provider state intact on error and surface a message so the
      // UI can choose how to react (we avoid forcing an error state that would
      // replace visible lists unexpectedly).
      final source = (ref.read(remoteSyncProvider) is RemoteSyncSupabase) ? 'Supabase' : 'Remote';
      ref.read(syncMessageProvider.notifier).state = '$source sync failed: ${e.toString()}';
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
      createdBy: s.createdBy,
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

  /// Update only the font size for a song (local + remote push of font_size)
  Future<void> updateFontSize(int id, double fontSize) async {
    final db = ref.read(localDbProvider);
    final all = await db.getAll();
    final idx = all.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final s = all[idx];
    final now = DateTime.now();
    final updated = Song(
      id: s.id,
      title: s.title,
      lyrics: s.lyrics,
      language: s.language,
      category: s.category,
      updatedAt: now,
      fontSize: fontSize,
      favorite: s.favorite,
      createdBy: s.createdBy,
    );

    // persist locally first
    await db.upsertSong(updated);

    // update in-memory state
    final current = state;
    if (current is AsyncData<List<Song>>) {
      final list = current.value.map((x) => x.id == id ? updated : x).toList();
      state = AsyncValue.data(list);
    }

    // push font size to remote (best-effort)
    final remote = ref.read(remoteSyncProvider);
    try {
      await remote.pushFontSize(id, fontSize);
    } catch (e) {
      ref.read(syncMessageProvider.notifier).state = 'Font-size push failed: ${e.toString()}';
    }
  }

  /// Create a new song (local + remote). Generates an id as max existing id + 1.
  Future<Song> createSong({
    required String title,
    required String lyrics,
    required String category,
    bool favorite = false,
  }) async {
    final db = ref.read(localDbProvider);
    final localUserId = await db.getLocalUserId();
    final all = await db.getAll();
    final maxId = all.isEmpty ? 0 : (all.map((s) => s.id).reduce((a, b) => a > b ? a : b));
    final id = maxId + 1;
    final now = DateTime.now();
    final song = Song(
      id: id,
      title: title,
      lyrics: lyrics,
      language: 'unknown',
      category: category,
      updatedAt: now,
      fontSize: null,
      favorite: favorite,
      createdBy: localUserId,
    );

    // push to remote then persist locally
    final remote = ref.read(remoteSyncProvider);
    try {
      await remote.pushSong(song.toMap());
    } catch (e) {
      // if remote fails, still persist locally but surface error via syncMessageProvider
      ref.read(syncMessageProvider.notifier).state = 'Create failed (remote): ${e.toString()}';
    }

    await db.upsertSong(song);
    // update state in-place
    final current = state;
    if (current is AsyncData<List<Song>>) {
      final list = List<Song>.from(current.value)..insert(0, song);
      state = AsyncValue.data(list);
    } else {
      await reloadAll();
    }
    return song;
  }

  /// Update an existing song (remote + local)
  Future<Song?> updateSong(Song updated) async {
    final db = ref.read(localDbProvider);
    final now = DateTime.now();
    final toSave = Song(
      id: updated.id,
      title: updated.title,
      lyrics: updated.lyrics,
      language: updated.language,
      category: updated.category,
      updatedAt: now,
      fontSize: updated.fontSize,
      favorite: updated.favorite,
      createdBy: updated.createdBy,
    );
    final remote = ref.read(remoteSyncProvider);
    try {
      await remote.pushSong(toSave.toMap());
    } catch (e) {
      ref.read(syncMessageProvider.notifier).state = 'Update failed (remote): ${e.toString()}';
    }
    await db.upsertSong(toSave);
    final current = state;
    if (current is AsyncData<List<Song>>) {
      final list = current.value.map((s) => s.id == toSave.id ? toSave : s).toList();
      state = AsyncValue.data(list);
    } else {
      await reloadAll();
    }
    return toSave;
  }

  /// Delete a song (remote + local)
  Future<void> deleteSong(int id) async {
    final remote = ref.read(remoteSyncProvider);
    try {
      await remote.deleteSong(id);
    } catch (e) {
      ref.read(syncMessageProvider.notifier).state = 'Delete failed (remote): ${e.toString()}';
    }
    await ref.read(localDbProvider).deleteSong(id);
    final current = state;
    if (current is AsyncData<List<Song>>) {
      final list = current.value.where((s) => s.id != id).toList();
      state = AsyncValue.data(list);
    } else {
      await reloadAll();
    }
  }
}
