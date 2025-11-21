import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/song_provider.dart';
import 'package:flutter/gestures.dart';
import '../models/song.dart';
// local_db is no longer used directly here; font-size persistence goes through provider
import 'add_song.dart';

class SongDetailScreen extends ConsumerStatefulWidget {
  final Song song;
  const SongDetailScreen({super.key, required this.song});

  @override
  ConsumerState<SongDetailScreen> createState() => _SongDetailScreenState();
}

class _SongDetailScreenState extends ConsumerState<SongDetailScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  double _fontSize = 16.0;
  double _initialFontSize = 16.0;
  Timer? _autoScrollTimer;
  bool _isAutoScrolling = false;
  bool _isScaling = false;
  int _scrollStep = 2; // pixels per auto-scroll tick (1..10)

  // Pinch-to-zoom adjusts `_fontSize`; explicit UI controls removed.

  void _startAutoScroll() {
    if (_isAutoScrolling) return;
    _isAutoScrolling = true;
    // Scroll small steps smoothly until the end
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (!_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      final current = _scrollCtrl.offset;
      if (current >= max) {
        _stopAutoScroll();
        return;
      }
      final next = (current + _scrollStep).clamp(0.0, max);
      try {
        await _scrollCtrl.animateTo(next,
            duration: const Duration(milliseconds: 280), curve: Curves.linear);
      } catch (_) {
        // animation cancelled or controller not attached
      }
    });
    setState(() {});
  }

  void _increaseScrollSpeed() {
    setState(() {
      _scrollStep = (_scrollStep + 1).clamp(1, 10);
    });
  }

  void _decreaseScrollSpeed() {
    setState(() {
      _scrollStep = (_scrollStep - 1).clamp(1, 10);
    });
  }

  Future<void> _zoomIn() async {
    setState(() {
      _fontSize = (_fontSize + 1).clamp(10.0, 48.0);
    });
    // persist and push only font size
    await ref.read(songsProvider.notifier).updateFontSize(_song.id, _fontSize);
    setState(() {
      _song = Song(
        id: _song.id,
        title: _song.title,
        lyrics: _song.lyrics,
        language: _song.language,
        category: _song.category,
        updatedAt: _song.updatedAt,
        fontSize: _fontSize,
        favorite: _song.favorite,
        createdBy: _song.createdBy,
      );
    });
  }

  Future<void> _zoomOut() async {
    setState(() {
      _fontSize = (_fontSize - 1).clamp(10.0, 48.0);
    });
    // persist and push only font size
    await ref.read(songsProvider.notifier).updateFontSize(_song.id, _fontSize);
    setState(() {
      _song = Song(
        id: _song.id,
        title: _song.title,
        lyrics: _song.lyrics,
        language: _song.language,
        category: _song.category,
        updatedAt: _song.updatedAt,
        fontSize: _fontSize,
        favorite: _song.favorite,
        createdBy: _song.createdBy,
      );
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _isAutoScrolling = false;
    setState(() {});
  }

  void _toggleAutoScroll() {
    if (_isAutoScrolling) {
      _stopAutoScroll();
    } else {
      // ensure start after frame so controller has positions
      WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoScroll());
    }
  }

  

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  late Song _song;
  String? _localUserId;

  @override
  void initState() {
    super.initState();
    // keep a local mutable copy of the song so we can update and persist
    _song = widget.song;
    _fontSize = _song.fontSize ?? _fontSize;
    // fetch local user id to determine edit permissions
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final id = await ref.read(localDbProvider).getLocalUserId();
      setState(() => _localUserId = id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = _song;
    return Scaffold(
      appBar: AppBar(title: Text(song.title), actions: [
        // Favorite toggle
        IconButton(
          tooltip: song.favorite ? 'Remove favorite' : 'Add favorite',
          icon: Icon(
            song.favorite ? Icons.favorite : Icons.favorite_border,
            color: song.favorite ? theme.colorScheme.primary : null,
          ),
          onPressed: () async {
            final updated = await ref.read(songsProvider.notifier).toggleFavorite(song.id);
            if (updated != null) setState(() => _song = updated);
          },
        ),
        // Show edit button only if current user is the creator
        if (_localUserId != null && _localUserId == song.createdBy)
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final edited = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddSongScreen(editing: _song)));
              if (edited is Song) {
                setState(() => _song = edited);
                await ref.read(songsProvider.notifier).reloadAll();
              }
            },
          ),
      ]),
      body: RawGestureDetector(
        gestures: <Type, GestureRecognizerFactory>{
          ScaleGestureRecognizer: GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
            () => ScaleGestureRecognizer(),
            (ScaleGestureRecognizer instance) {
              instance.onStart = (details) {
                _initialFontSize = _fontSize;
                setState(() { _isScaling = true; });
              };
              instance.onUpdate = (details) {
                if (details.scale != 1.0) {
                  setState(() {
                    _fontSize = (_initialFontSize * details.scale).clamp(10.0, 48.0);
                  });
                }
              };
              instance.onEnd = (details) {
                setState(() { _isScaling = false; });
                // persist font size for this song
                // persist and push only font size
                ref.read(songsProvider.notifier).updateFontSize(_song.id, _fontSize).then((_) async {
                  setState(() {
                    _song = Song(
                      id: _song.id,
                      title: _song.title,
                      lyrics: _song.lyrics,
                      language: _song.language,
                      category: _song.category,
                      updatedAt: _song.updatedAt,
                      fontSize: _fontSize,
                      favorite: _song.favorite,
                      createdBy: _song.createdBy,
                    );
                  });
                });
              };
              // Note: ScaleGestureRecognizer starts when appropriate pointer sequence occurs.
            },
          ),
        },
        child: Stack(
          children: [
            Container(
              color: Colors.transparent,
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                physics: _isScaling ? const NeverScrollableScrollPhysics() : null,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Text('${song.category} • ${song.language}', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 16),
                    // Use non-selectable Text to avoid SelectionGestureRecognizer
                    Text(
                      song.lyrics,
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: _fontSize),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
            // Mid-right zoom controls: show both variants so user can preview A and B
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Variant B: vertical white pill with stacked icons
                            Container(
                              color: Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Zoom in',
                            onPressed: _zoomIn,
                            icon: const Icon(Icons.zoom_in),
                            iconSize: 28,
                            splashRadius: 30,
                            padding: const EdgeInsets.all(6),
                          ),
                          const SizedBox(height: 4),
                          Container(height: 1, width: 34, color: Colors.grey.shade300),
                          const SizedBox(height: 4),
                          IconButton(
                            tooltip: 'Zoom out',
                            onPressed: _zoomOut,
                            icon: const Icon(Icons.zoom_out),
                            iconSize: 28,
                            splashRadius: 30,
                            padding: const EdgeInsets.all(6),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Material(
        elevation: 4,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Autoscroll controls: flat rectangular panel (no rounded corners, no elevation)
                Center(
                  child: Container(
                                color: Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Decrease speed: small outlined square button
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.12)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: _decreaseScrollSpeed,
                            child: const Icon(Icons.remove, size: 22),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text('Speed ${_scrollStep}px', style: Theme.of(context).textTheme.bodyMedium),
                        ),
                        // Increase speed: small outlined square button
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.12)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: _increaseScrollSpeed,
                            child: const Icon(Icons.add, size: 22),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Start/Stop autoscroll: larger outlined label button (non-elevated)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.primary,
                            backgroundColor: Colors.transparent,
                            side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.06)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            minimumSize: const Size(84, 48),
                          ),
                          onPressed: _toggleAutoScroll,
                          icon: Icon(_isAutoScrolling ? Icons.pause : Icons.play_arrow),
                          label: Text(_isAutoScrolling ? 'Stop' : 'Autoscroll', style: TextStyle(fontSize: 16)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // No FAB: zoom is handled by pinch gestures; autoscroll controls live in bottom bar.
    );
  }

  
}
