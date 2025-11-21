import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/song_provider.dart';
import '../models/song.dart';
import 'song_detail.dart';

class CategoryListScreen extends ConsumerStatefulWidget {
  const CategoryListScreen({super.key});

  static const categories = [
    'devotional', 'romantic', 'folk', 'patriotic', 'classic', 'pop', 'kids'
  ];

  @override
  ConsumerState<CategoryListScreen> createState() => _CategoryListScreenState();
}

class _CategoryListScreenState extends ConsumerState<CategoryListScreen> {
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    // load all songs on first build
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // ensure songs are loaded
      await ref.read(songsProvider.notifier).reloadAll();
      // restore last selected category if present
      try {
        final db = ref.read(localDbProvider);
        final last = await db.getLastSelectedCategory();
        if (last != null && CategoryListScreen.categories.contains(last)) {
          setState(() => _selectedCategory = last);
          ref.read(songsProvider.notifier).filterByCategory(last);
        }
      } catch (_) {
        // ignore if settings box isn't ready yet
      }
    });
  }

  void _selectCategory(String? cat) {
    setState(() => _selectedCategory = cat);
    if (cat == null) {
      ref.read(songsProvider.notifier).reloadAll();
    } else {
      ref.read(songsProvider.notifier).filterByCategory(cat);
    }
    // persist selection (fire-and-forget)
    try {
      ref.read(localDbProvider).setLastSelectedCategory(cat);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Listen for startup/remote sync messages and show a SnackBar when one appears
    ref.listen<String?>(
      syncMessageProvider,
      (previous, next) {
        if (next != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(next),
              duration: const Duration(milliseconds: 1200),
            ));
            // Reapply the current category filter (or reload all) so the UI doesn't show the full list
            // after a remote sync overrides provider state.
            if (_selectedCategory == null) {
              ref.read(songsProvider.notifier).reloadAll();
            } else {
              ref.read(songsProvider.notifier).filterByCategory(_selectedCategory!);
            }
            // clear message after showing
            ref.read(syncMessageProvider.notifier).state = null;
          });
        }
      },
    );

    final songsAsync = ref.watch(songsProvider);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lyrics Categories'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () => ref.read(songsProvider.notifier).refreshFromRemote(),
            tooltip: 'Sync updates',
          ),
          // Theme toggle: light <-> dark
          IconButton(
            icon: Icon(ref.watch(themeModeProvider) == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () {
              final cur = ref.read(themeModeProvider.notifier).state;
              final next = cur == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
              ref.read(themeModeProvider.notifier).state = next;
            },
            tooltip: 'Toggle theme',
          ),
        ],
      ),
      body: Column(
        children: [
          // Top category strip
          SizedBox(
            height: 96,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: ChoiceChip(
                      label: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text('All', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      selected: _selectedCategory == null,
                      onSelected: (_) => _selectCategory(null),
                      selectedColor: isDark
                          ? theme.colorScheme.primary.withOpacity(0.30)
                          : theme.colorScheme.primary.withOpacity(0.14),
                      side: _selectedCategory == null
                          ? BorderSide(color: theme.colorScheme.primary.withOpacity(0.22))
                          : BorderSide.none,
                      labelStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _selectedCategory == null ? theme.colorScheme.onPrimary : null,
                      ),
                    ),
                  ),
                  for (final cat in CategoryListScreen.categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: ChoiceChip(
                        label: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Text(cat.toUpperCase(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                        selected: _selectedCategory == cat,
                        onSelected: (_) => _selectCategory(cat),
                        selectedColor: isDark
                            ? theme.colorScheme.primary.withOpacity(0.30)
                            : theme.colorScheme.primary.withOpacity(0.14),
                        side: _selectedCategory == cat
                            ? BorderSide(color: theme.colorScheme.primary.withOpacity(0.26))
                            : BorderSide.none,
                        labelStyle: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _selectedCategory == cat ? theme.colorScheme.onPrimary : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Divider
          Divider(height: 1, color: theme.dividerColor),

          // Songs list (animated when switching categories)
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) {
                // horizontal slide from right with fade
                final curved = CurvedAnimation(parent: anim, curve: Curves.easeInOut);
                final offsetAnim = Tween<Offset>(begin: const Offset(0.25, 0), end: Offset.zero).animate(curved);
                return SlideTransition(position: offsetAnim, child: FadeTransition(opacity: anim, child: child));
              },
              child: Container(
                key: ValueKey<String?>(_selectedCategory ?? 'all'),
                child: Builder(builder: (context) {
                  return RefreshIndicator(
                    onRefresh: () async {
                      await ref.read(songsProvider.notifier).refreshFromRemote();
                    },
                    child: songsAsync.when(
                      loading: () => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                      ),
                      error: (e, _) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: Center(child: Text('Error: $e')),
                        ),
                      ),
                      data: (songs) {
                        if (songs.isEmpty) {
                          return SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              height: MediaQuery.of(context).size.height * 0.5,
                              child: const Center(child: Text('No songs available')),
                            ),
                          );
                        }
                        return ListView.separated(
                          itemCount: songs.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final Song s = songs[i];
                            return ListTile(
                              leading: const Icon(Icons.music_note),
                              title: Text(s.title),
                              subtitle: Text('${s.category} • ${s.language}'),
                              trailing: IconButton(
                                tooltip: s.favorite ? 'Remove favorite' : 'Add favorite',
                                icon: Icon(
                                  s.favorite ? Icons.favorite : Icons.favorite_border,
                                  color: s.favorite ? theme.colorScheme.primary : null,
                                ),
                                onPressed: () async {
                                  await ref.read(songsProvider.notifier).toggleFavorite(s.id);
                                },
                              ),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => SongDetailScreen(song: s)),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
