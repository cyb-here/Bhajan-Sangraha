import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
import '../models/song.dart';
import '../services/local_db.dart';
import '../services/remote_sync_base.dart';
import '../services/remote_sync_supabase.dart';
import '../config.dart';

/// Provider for the local Hive database service
final localDbProvider = Provider<LocalDb>((ref) => LocalDb());

/// Provider for the remote sync service
final remoteSyncProvider = Provider<RemoteSyncBase>((ref) {
  // Enforce Supabase configuration
  if (SUPABASE_URL.isEmpty || SUPABASE_ANON_KEY.isEmpty) {
    throw Exception('Supabase not configured. Please set SUPABASE_URL and SUPABASE_ANON_KEY in config.dart');
  }
  
  final db = ref.read(localDbProvider);
  return RemoteSyncSupabase(localDb: db, supabaseUrl: SUPABASE_URL, anonKey: SUPABASE_ANON_KEY);
});

/// StateNotifierProvider that manages the list of songs
final songsProvider =
    StateNotifierProvider<SongsNotifier, AsyncValue<List<Song>>>((ref) {
  return SongsNotifier(ref);
});

/// Provider to surface short sync status messages to the UI (snackbars)
final syncMessageProvider = StateProvider<String?>((ref) => null);

/// Provider for sync status: 'idle', 'syncing', 'failed'
final syncStatusProvider = StateProvider<String>((ref) => 'idle');

/// Provider that stores last successful sync time.
final lastSyncedProvider = StateProvider<DateTime?>((ref) => null);

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
    
    // Apply saved order if exists
    final savedOrder = await db.getSongOrder();
    final sortedSongs = _applySavedOrder(songs, savedOrder);
    
    state = AsyncValue.data(sortedSongs);
    
    // attempt a remote sync on app startup (refreshFromRemote will surface messages)
    // Hydrate lastSynced provider from persisted settings so UI can show accurate info
    try {
      final persisted = await db.getLastSynced();
      ref.read(lastSyncedProvider.notifier).state = persisted;
    } catch (_) {}

    try {
      await refreshFromRemote();
    } catch (_) {
      // message already set by refreshFromRemote
    }
  }
  
  List<Song> _applySavedOrder(List<Song> songs, List<int> order) {
    if (order.isEmpty) return songs;
    
    final Map<int, Song> map = {for (var s in songs) s.id: s};
    final List<Song> ordered = [];
    
    // Add songs in the saved order
    for (final id in order) {
      if (map.containsKey(id)) {
        ordered.add(map[id]!);
        map.remove(id);
      }
    }
    
    // Append any remaining songs (new ones or missed ones)
    ordered.addAll(map.values);
    
    return ordered;
  }

  /// Public wrapper to reload all songs from Hive
  Future<void> reloadAll() async {
    final db = ref.read(localDbProvider);
    final songs = await db.getAll();
    final savedOrder = await db.getSongOrder();
    final sortedSongs = _applySavedOrder(songs, savedOrder);
    state = AsyncValue.data(sortedSongs);
  }

  Future<void> reorderSongs(List<Song> newOrder) async {
     state = AsyncValue.data(newOrder);
     final ids = newOrder.map((s) => s.id).toList();
     await ref.read(localDbProvider).saveSongOrder(ids);
  }

  /// Refresh songs from remote Supabase
  /// Returns the number of applied updates.
  Future<int> refreshFromRemote() async {
    // Update sync status so UI can show spinner / failure state
    ref.read(syncStatusProvider.notifier).state = 'syncing';
    try {
      final sync = ref.read(remoteSyncProvider);
      final applied = await sync.sync();

      // mark success
      ref.read(syncStatusProvider.notifier).state = 'idle';
      final nowUtc = DateTime.now().toUtc();
      ref.read(lastSyncedProvider.notifier).state = nowUtc;
      // Persist last synced timestamp to local settings so it survives restarts
      try {
        await ref.read(localDbProvider).setLastSynced(nowUtc);
      } catch (_) {
        // ignore persistence errors
      }

      // surface a short message for UI listeners (manual or startup sync)
      ref.read(syncMessageProvider.notifier).state = 'Supabase sync completed: $applied updates';
      return applied;
    } catch (e) {
      // Keep the provider state intact on error and surface a message so the
      // UI can choose how to react (we avoid forcing an error state that would
      // replace visible lists unexpectedly).
      ref.read(syncStatusProvider.notifier).state = 'failed';
      ref.read(syncMessageProvider.notifier).state = 'Supabase sync failed: ${e.toString()}';
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
    
    // Apply order if possible, though typically filtering by category breaks the global order
    // If we want to support ordering within categories, we'd need a per-category order storage.
    // For now, we just apply the global order to the filtered subset.
    final db = ref.read(localDbProvider);
    final savedOrder = await db.getSongOrder();
    final sortedResults = _applySavedOrder(results, savedOrder);
    
    state = AsyncValue.data(sortedResults);
  }

  /// Show only favorite songs from local DB
  Future<void> filterFavorites() async {
    final db = ref.read(localDbProvider);
    final all = await db.getAll();
    final results = all.where((s) => s.favorite).toList();
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
      updatedAt: DateTime.now(), // Update time for sorting
      fontSize: s.fontSize,
      favorite: newVal,
      createdBy: s.createdBy,
    );
    await db.upsertSong(updated);
    
    // Push favorite status to remote Supabase
    final remote = ref.read(remoteSyncProvider);
    try {
        await remote.pushSong(updated.toMap());
    } catch (e) {
        ref.read(syncMessageProvider.notifier).state = 'Favorite sync failed: ${e.toString()}';
    }

    // Update state and if becoming favorite, move to top of list (persisted order)
    if (state is AsyncData<List<Song>>) {
        var currentList = (state as AsyncData<List<Song>>).value;
        
        // 1. Update the song object in the list
        currentList = currentList.map((x) => x.id == id ? updated : x).toList();
        
        // 2. If favorited, move to top
        if (newVal) {
            final index = currentList.indexWhere((x) => x.id == id);
            if (index != -1) {
                final item = currentList.removeAt(index);
                currentList.insert(0, item);
                
                // Save this new order to local DB
                final ids = currentList.map((x) => x.id).toList();
                await db.saveSongOrder(ids);
            }
        }
        
        state = AsyncValue.data(currentList);
    } else {
        // Fallback if state isn't ready
        await reloadAll();
    }
    
    return updated;
  }

  /// Update only the font size for a song (LOCAL only)
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

    // We are NO LONGER pushing font size to remote to avoid schema errors and extra API calls.
    // Font size preference remains local to the device.
  }

  /// Create a new song (local + remote). Generates an id as max existing id + 1.
  Future<Song> createSong({
    required String title,
    required String lyrics,
    required String category,
    bool favorite = false,
  }) async {
    final db = ref.read(localDbProvider);
    // Get current authenticated user ID from Supabase instead of local placeholder
    final user = Supabase.instance.client.auth.currentUser;
    // Fallback to local ID if somehow not logged in (though UI prevents this)
    final userId = user?.id ?? await db.getLocalUserId();
    
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
      createdBy: userId,
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
