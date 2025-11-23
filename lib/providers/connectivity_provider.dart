import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stream provider that emits the current [ConnectivityResult].
final connectivityStreamProvider = StreamProvider<ConnectivityResult>((ref) {
  final conn = Connectivity();
  return conn.onConnectivityChanged;
});

/// Simple bool provider indicating whether we are "online".
///
/// Note: This treats any connectivity other than [ConnectivityResult.none]
/// as online. Depending on your needs you may want to perform an actual
/// network probe to verify internet access.
final isOnlineProvider = Provider<bool>((ref) {
  final async = ref.watch(connectivityStreamProvider);
  return async.when(
    data: (value) => value != ConnectivityResult.none,
    loading: () => true,
    error: (_, __) => true,
  );
});
