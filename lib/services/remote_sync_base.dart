abstract class RemoteSyncBase {
  /// Fetch updates and apply them to local DB. Returns number of applied updates.
  Future<int> sync();

  /// Push (create or update) a single song to the remote source.
  Future<void> pushSong(dynamic song);

  /// Delete a song by id from the remote source.
  Future<void> deleteSong(int id);
}
