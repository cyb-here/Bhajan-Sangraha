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
    final themeOption = ref.watch(themeOptionProvider);

    // Accent color (seed) — user selectable
    final accent = ref.watch(accentColorProvider);

    // Base light theme uses the accent as the colorScheme seed
    final lightTheme = ThemeData(
      colorSchemeSeed: accent,
      useMaterial3: true,
      fontFamily: 'Roboto',
    );

    // Default dark theme (uses accent as primary)
    final defaultDark = ThemeData.from(
      colorScheme: ColorScheme.dark(
        primary: accent,
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
    );

    // Dark gray theme variant (less pure black, more gray)
    final darkGray = ThemeData.from(
      colorScheme: ColorScheme.dark(
        primary: accent,
        background: const Color(0xFF202124),
        surface: const Color(0xFF2B2B2B),
        onSurface: Colors.white,
      ),
      useMaterial3: true,
    ).copyWith(
      scaffoldBackgroundColor: const Color(0xFF202124),
      canvasColor: const Color(0xFF2B2B2B),
      cardColor: const Color(0xFF2B2B2B),
      dialogBackgroundColor: const Color(0xFF2B2B2B),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF2B2B2B),
        elevation: 0,
        foregroundColor: Colors.white,
      ),
    );

    // Choose which dark theme to supply to MaterialApp
    final ThemeData chosenDark = themeOption == AppThemeOption.darkGray ? darkGray : defaultDark;

    // Determine ThemeMode: light => ThemeMode.light, others use ThemeMode.dark
    final themeMode = themeOption == AppThemeOption.light ? ThemeMode.light : ThemeMode.dark;

    return MaterialApp(
      // debugShowCheckedModeBanner: false,
      title: 'Lyrics App',
      theme: lightTheme,
      darkTheme: chosenDark,
      themeMode: themeMode,
      home: const CategoryListScreen(),
    );
  }
}
