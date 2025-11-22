import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: SUPABASE_URL,
    anonKey: SUPABASE_ANON_KEY,
  );
}

SupabaseClient getSupabaseClient() => Supabase.instance.client;
