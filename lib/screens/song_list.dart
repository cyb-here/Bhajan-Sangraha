import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/song_provider.dart';
import '../models/song.dart';
import 'song_detail.dart';

class SongListScreen extends ConsumerStatefulWidget {
  final String? category;
  const SongListScreen({super.key, this.category});

  @override
  ConsumerState<SongListScreen> createState() => _SongListScreenState();
}

class _SongListScreenState extends ConsumerState<SongListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _isReordering = false;

  /// Reload Hive data every time this screen becomes active
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = ref.read(songsProvider.notifier);

    if (widget.category != null) {
      notifier.filterByCategory(widget.category!); // reload Hive + filter
    } else {
      notifier.reloadAll(); // reload Hive for all songs
    }
  }

  void _onSearchChanged(String val) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final query = val.trim();
      if (query.isEmpty) {
        ref.read(songsProvider.notifier).reloadAll();
      } else {
        ref.read(songsProvider.notifier).search(query);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(songsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category != null ? 'Category: ${widget.category}' : 'All Songs'),
        actions: [
          IconButton(
            icon: Icon(_isReordering ? Icons.done : Icons.sort),
            tooltip: _isReordering ? 'Finish reordering' : 'Reorder songs',
            onPressed: () {
              setState(() {
                _isReordering = !_isReordering;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search song titles',
              ),
            ),
          ),
          Expanded(
            child: songsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (songs) {
                if (songs.isEmpty) {
                   return const Center(child: Text('No songs found'));
                }
                
                // In reorder mode, we work with the list as provided by the provider (which handles sorting internally if we persist order)
                // For now, we assume the provider returns them in the desired display order.
                // However, since we have complex sorting logic (favorites first), reordering might be tricky if we don't persist it properly.
                // For this implementation, we'll assume the user wants to manually order the list and we save that order.
                // BUT: The current provider logic sorts by ID/Favorite dynamically.
                // To support custom order, we need the provider to sort by a persisted index.
                
                final currentList = List<Song>.from(songs);
                
                if (_isReordering) {
                  return ReorderableListView(
                    onReorder: (oldIndex, newIndex) {
                       if (oldIndex < newIndex) {
                        newIndex -= 1;
                      }
                      final item = currentList.removeAt(oldIndex);
                      currentList.insert(newIndex, item);
                      
                      // Update state immediately to reflect changes in UI
                      // In a real app, we'd update the provider's state here.
                      // But since we need to persist this, we should call a method on the notifier.
                      ref.read(songsProvider.notifier).reorderSongs(currentList);
                    },
                    children: [
                      for (final s in currentList)
                        ListTile(
                          key: ValueKey(s.id),
                          leading: const Icon(Icons.drag_handle),
                          title: Text(s.title),
                          subtitle: Text('${s.category} • ${s.language}'),
                        ),
                    ],
                  );
                }

                return ListView.separated(
                  itemCount: currentList.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final Song s = currentList[i];
                    return ListTile(
                      leading: const Icon(Icons.music_note),
                      title: Text(s.title),
                      subtitle: Text('${s.category} • ${s.language}'),
                      trailing: IconButton(
                        tooltip: s.favorite ? 'Remove favorite' : 'Add favorite',
                        icon: Icon(
                          s.favorite ? Icons.favorite : Icons.favorite_border,
                          color: s.favorite ? Theme.of(context).colorScheme.primary : null,
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
          ),
        ],
      ),
    );
  }
}
