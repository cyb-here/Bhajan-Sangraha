abstract class RemoteSyncBase {
  /// Fetch updates and apply them to local DB. Returns number of applied updates.
  Future<int> sync();

  /// Push (create or update) a single song to the remote source.
  Future<void> pushSong(dynamic song);

  /// Delete a song by id from the remote source.
  Future<void> deleteSong(int id);

  /// Push only the font size for a given song id. Useful when font size
  /// changes should be propagated without sending the full song payload.
  Future<void> pushFontSize(int id, double fontSize);
}
