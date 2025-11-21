import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/song_provider.dart';

class AddSongScreen extends ConsumerStatefulWidget {
  const AddSongScreen({super.key});

  @override
  ConsumerState<AddSongScreen> createState() => _AddSongScreenState();
}

class _AddSongScreenState extends ConsumerState<AddSongScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtl = TextEditingController();
  final _lyricsCtl = TextEditingController();
  bool _favorite = false;
  bool _saving = false;

  // Categories (kept local to avoid cross-file imports)
  static const categories = [
    'devotional', 'romantic', 'folk', 'patriotic', 'classic', 'pop', 'kids'
  ];
  String? _selectedCategory = categories.first;

  @override
  void dispose() {
    _titleCtl.dispose();
    _lyricsCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final title = _titleCtl.text.trim();
    final lyrics = _lyricsCtl.text.trim();
    final category = _selectedCategory ?? 'uncategorized';

    try {
      final song = await ref.read(songsProvider.notifier).createSong(
        title: title,
        lyrics: lyrics,
        category: category,
        favorite: _favorite,
      );
      if (mounted) {
        Navigator.of(context).pop(song);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Create failed: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Song')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _titleCtl,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _lyricsCtl,
                decoration: const InputDecoration(labelText: 'Lyrics'),
                maxLines: 6,
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c.toUpperCase()))).toList(),
                onChanged: (v) => setState(() => _selectedCategory = v),
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(value: _favorite, onChanged: (v) => setState(() => _favorite = v ?? false)),
                  const SizedBox(width: 8),
                  const Text('Favorite'),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving ? const CircularProgressIndicator() : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
