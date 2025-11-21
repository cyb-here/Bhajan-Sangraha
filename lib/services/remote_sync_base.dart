abstract class RemoteSyncBase {
  /// Fetch updates and apply them to local DB. Returns number of applied updates.
  Future<int> sync();
}
