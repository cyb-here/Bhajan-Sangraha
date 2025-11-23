import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/song_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/auth_provider.dart';
import 'package:intl/intl.dart';
import '../models/song.dart';
import 'song_detail.dart';
import 'add_song.dart';
import 'login_screen.dart';

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
  bool _isReordering = false;
  bool _showFavorites = false;
  final ScrollController _listController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  int? _highlightedSongId;

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

  Future<void> _openSearch(BuildContext context) async {
    // Build a search function that queries the local DB. Captures `ref`.
    Future<List<Song>> searchFn(String q) async {
      final db = ref.read(localDbProvider);
      final all = await db.getAll();
      final lower = q.toLowerCase();
      return all.where((s) => s.title.toLowerCase().contains(lower) || s.lyrics.toLowerCase().contains(lower)).toList();
    }

    final Song? picked = await showSearch<Song?>(
      context: context,
      delegate: SongsSearchDelegate(searchFn),
    );

    if (picked != null) {
      // Directly open the song detail when a search result is selected.
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => SongDetailScreen(song: picked)));
    }
  }

  Future<void> _scrollToSong(Song song) async {
    // Try to find the key for this song; if not present, attempt to reload list and then try.
    final key = _itemKeys[song.id];
    if (key != null && key.currentContext != null) {
      await Scrollable.ensureVisible(key.currentContext!, duration: const Duration(milliseconds: 300), alignment: 0.3);
      setState(() => _highlightedSongId = song.id);
      // Remove highlight after delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _highlightedSongId = null);
      });
      return;
    }

    // Fallback: try to compute index and scroll by offset if ListView is present
    final songsAsync = ref.read(songsProvider);
    if (songsAsync is AsyncData<List<Song>>) {
      final list = songsAsync.value;
      final idx = list.indexWhere((s) => s.id == song.id);
      if (idx != -1) {
        // Approximate scroll by item extent (may vary) — use ensureVisible when keys are available
        final position = idx * 72.0; // assumed approx tile height
        await _listController.animateTo(position, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
        setState(() => _highlightedSongId = song.id);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _highlightedSongId = null);
        });
        return;
      }
    }
  }

  Future<void> _toggleFavorites() async {
    setState(() => _showFavorites = !_showFavorites);
    if (_showFavorites) {
      // request the notifier to filter favorites
      try {
        await ref.read(songsProvider.notifier).filterFavorites();
      } catch (_) {
        await ref.read(songsProvider.notifier).reloadAll();
      }
    } else {
      // restore previous view (category or all)
      if (_selectedCategory == null) {
        await ref.read(songsProvider.notifier).reloadAll();
      } else {
        await ref.read(songsProvider.notifier).filterByCategory(_selectedCategory!);
      }
    }
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
    final userAsync = ref.watch(userProvider);
    final user = userAsync.asData?.value;

    // Listen for startup/remote sync messages and show a SnackBar when one appears.
    // If the message indicates failure, surface a retry action.
    ref.listen<String?>(
      syncMessageProvider,
      (previous, next) {
        if (next != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final isFailure = next.toLowerCase().contains('fail');
            final snack = SnackBar(
              content: Text(next),
              duration: const Duration(milliseconds: 1800),
              action: isFailure
                  ? SnackBarAction(
                      label: 'Retry',
                      onPressed: () => ref.read(songsProvider.notifier).refreshFromRemote(),
                    )
                  : null,
            );
            ScaffoldMessenger.of(context).showSnackBar(snack);

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
    final isOnline = ref.watch(isOnlineProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bhajan Sangraha'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              if (user == null) {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
              } else {
                // open Add Song screen
                final res = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddSongScreen()));
                if (res != null) {
                  // show brief confirmation
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Song added')));
                  // reload list
                  ref.read(songsProvider.notifier).reloadAll();
                }
              }
            },
            tooltip: 'Add song',
          ),
          // Sync moved into overflow menu
          // Overflow menu to keep AppBar tidy
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'toggle_favs') { await _toggleFavorites(); return; }
              if (v == 'toggle_theme') {
                final cur = ref.read(themeModeProvider.notifier).state;
                final next = cur == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
                ref.read(themeModeProvider.notifier).state = next;
                return;
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'sync', child: Row(children: [const Icon(Icons.sync), const SizedBox(width: 8), const Text('Sync updates')])),
              PopupMenuItem(value: 'toggle_favs', child: Row(children: [Icon(_showFavorites ? Icons.favorite : Icons.favorite_border), const SizedBox(width: 8), Text(_showFavorites ? 'Show all' : 'Show favorites')])),
              PopupMenuItem(value: 'toggle_theme', child: Row(children: [Icon(ref.watch(themeModeProvider) == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode), const SizedBox(width: 8), const Text('Toggle theme')])),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openSearch(context),
        tooltip: 'Search songs',
        child: const Icon(Icons.search),
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

          // Sync status row (shows syncing/failed/last-synced) + reorder toggle
          Builder(builder: (context) {
            final status = ref.watch(syncStatusProvider);
            final last = ref.watch(lastSyncedProvider);

            // Build a left-aligned sync/last-synced widget and move reorder to the right
            final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12);
            Widget leftContent;
            if (status == 'syncing') {
              leftContent = Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.0)),
                  SizedBox(width: 8),
                  Text('Syncing...', style: TextStyle(fontSize: 12)),
                ],
              );
            } else if (status == 'failed') {
              leftContent = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => ref.read(songsProvider.notifier).refreshFromRemote(),
                    child: const Text('Retry sync', style: TextStyle(fontSize: 12)),
                  ),
                ],
              );
            } else if (last != null) {
              final text = DateFormat('yyyy-MM-dd HH:mm').format(last);
              leftContent = Text('Last synced: $text', style: textStyle?.copyWith(color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.8)));
            } else {
              leftContent = const SizedBox.shrink();
            }

            return Container(
              width: double.infinity,
              color: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  // Left: last-synced or status
                  Expanded(child: Align(alignment: Alignment.centerLeft, child: leftContent)),

                  // Right: Reorder toggle button (now aligned right for better discoverability)
                  IconButton(
                    icon: Icon(_isReordering ? Icons.check : Icons.drag_handle),
                    tooltip: _isReordering ? 'Done rearranging' : 'Rearrange list',
                    onPressed: () {
                      setState(() => _isReordering = !_isReordering);
                      // if leaving reorder mode, reload to ensure stable order in provider
                      if (!_isReordering) {
                        ref.read(songsProvider.notifier).reloadAll();
                      }
                    },
                  ),
                ],
              ),
            );
          }),

          // Offline indicator (small banner)
          if (!isOnline)
            Container(
              width: double.infinity,
              color: Colors.red.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Offline — changes saved locally', style: TextStyle(color: Colors.white)),
                  TextButton(
                    onPressed: () => ref.read(songsProvider.notifier).refreshFromRemote(),
                    child: const Text('Retry', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          // Divider
          Divider(height: 1, color: theme.dividerColor),

          // Songs list
          Expanded(
            child: Container(
              key: ValueKey<String?>(_selectedCategory ?? 'all'),
              child: Builder(builder: (context) {
                Widget buildList(List<Song> songs) {
                   if (songs.isEmpty) {
                      return const Center(child: Text('No songs available'));
                    }

                    // Always sort favorites first, preserving relative order for the rest
                    final displayList = List<Song>.from(songs);
                    displayList.sort((a, b) {
                      if (a.favorite && !b.favorite) return -1;
                      if (!a.favorite && b.favorite) return 1;
                      return 0; // Keep provider's order (persisted order)
                    });

                    if (_isReordering) {
                      return ReorderableListView(
                        onReorder: (oldIndex, newIndex) {
                          if (oldIndex < newIndex) newIndex -= 1;
                          final item = displayList.removeAt(oldIndex);
                          displayList.insert(newIndex, item);
                          
                          // Persist new order
                          ref.read(songsProvider.notifier).reorderSongs(displayList);
                        },
                        children: [
                          for (final s in displayList)
                            ListTile(
                              key: _itemKeys.putIfAbsent(s.id, () => GlobalKey()),
                              leading: const Icon(Icons.drag_handle),
                              title: Text(s.title),
                              subtitle: Text('${s.category} • ${s.language}'),
                            ),
                        ],
                      );
                    }

                    return ListView.separated(
                      controller: _listController,
                      itemCount: displayList.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final Song s = displayList[i];
                        final highlighted = _highlightedSongId != null && _highlightedSongId == s.id;
                        return Container(
                          key: _itemKeys.putIfAbsent(s.id, () => GlobalKey()),
                          color: highlighted ? theme.colorScheme.primary.withOpacity(0.12) : null,
                          child: ListTile(
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
                          ),
                        );
                      },
                    );
                }

                // If reordering, show just the list (no pull-to-refresh)
                if (_isReordering) {
                   return songsAsync.when(
                     loading: () => const Center(child: CircularProgressIndicator()),
                     error: (e, _) => Center(child: Text('Error: $e')),
                     data: buildList,
                   );
                }

                // Normal mode: wrap in RefreshIndicator
                return RefreshIndicator(
                  onRefresh: () async {
                    await ref.read(songsProvider.notifier).refreshFromRemote();
                  },
                  child: songsAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: buildList,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// SearchDelegate that queries a provided async search function and shows results.
class SongsSearchDelegate extends SearchDelegate<Song?> {
  final Future<List<Song>> Function(String) searchFn;

  SongsSearchDelegate(this.searchFn) : super(searchFieldLabel: 'Search songs');

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget buildResults(BuildContext context) {
    return FutureBuilder<List<Song>>(
      future: searchFn(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('No results'));
        final results = snapshot.data!;
        return ListView.separated(
          itemCount: results.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final s = results[index];
            return ListTile(
              title: Text(s.title),
              subtitle: Text('${s.category} • ${s.language}'),
              onTap: () => close(context, s),
            );
          },
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) return const Center(child: Text('Type to search'));
    return FutureBuilder<List<Song>>(
      future: searchFn(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('No suggestions'));
        final suggestions = snapshot.data!;
        return ListView.builder(
          itemCount: suggestions.length,
          itemBuilder: (context, i) {
            final s = suggestions[i];
            return ListTile(
              title: Text(s.title),
              subtitle: Text(s.category),
              onTap: () => close(context, s),
            );
          },
        );
      },
    );
  }

}
