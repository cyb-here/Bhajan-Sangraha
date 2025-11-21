// Supabase SDK not required for REST-based sync in this project.
// Keeping lightweight helpers so code that calls `initSupabase()`
// won't fail if Supabase isn't configured.

Future<void> initSupabase() async {
  // No-op: REST-based sync is used. If you later want the SDK,
  // add `supabase_flutter` to `pubspec.yaml` again and restore
  // the original implementation.
  return;
}

// `getSupabaseClient()` intentionally left unimplemented to avoid
// introducing the SDK dependency. If you need the client, re-add
// `supabase_flutter` and implement this helper.
Never getSupabaseClient() => throw UnsupportedError(
    'Supabase SDK not enabled. Add supabase_flutter to pubspec.yaml.');
