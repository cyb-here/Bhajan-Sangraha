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
              data: (songs) => ListView.separated(
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
              ),
            ),
          ),
        ],
      ),
      // Sync button intentionally shown on categories page only.
    );
  }
}
