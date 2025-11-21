import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/category_list.dart';
import 'providers/song_provider.dart';
import 'services/supabase_service.dart';

// Initialize Supabase here if config is provided.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const ProviderScope(child: LyricsApp()));
}

class LyricsApp extends ConsumerWidget {
  const LyricsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      // debugShowCheckedModeBanner: false,
      title: 'Lyrics App',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4CAF50),
        useMaterial3: true,
        fontFamily: 'Roboto', // add Marathi font later if needed
      ),
      darkTheme: ThemeData.from(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4CAF50),
          background: Colors.black,
          surface: Colors.black,
          onSurface: Colors.white,
        ),
        useMaterial3: true,
      ).copyWith(
        scaffoldBackgroundColor: Colors.black,
        canvasColor: Colors.black,
        cardColor: Colors.black,
        dialogBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
      ),
      themeMode: themeMode,
      home: const CategoryListScreen(),
    );
  }
}
