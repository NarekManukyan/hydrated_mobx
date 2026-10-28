import 'package:flutter/material.dart';

import '../app/app_storages.dart';
import '../stores/recent_stores.dart';
import '../widgets/demo_page.dart';
import '../widgets/live_box_keys.dart';

const _kItemCount = 10;

class EvictionPage extends StatefulWidget {
  const EvictionPage({super.key});

  @override
  State<EvictionPage> createState() => _EvictionPageState();
}

class _EvictionPageState extends State<EvictionPage> {
  final _viewed = <int>[];
  bool _rebuilding = false;

  // Open for the page's lifetime, so a rebuild moves it to the new box.
  final _pinned = PinnedNoteStore(appStorages.recent);

  @override
  void dispose() {
    _pinned.dispose();
    super.dispose();
  }

  /// Opens item [index]'s cache entry, counts a view and closes it again.
  Future<void> _view(int index) async {
    final store = RecentItemStore('item_$index', appStorages.recent)..view();
    await store.flush();
    store.dispose();
    if (!mounted) return;
    setState(
      () => _viewed
        ..remove(index)
        ..add(index),
    );
  }

  Future<void> _rebuild() async {
    setState(() => _rebuilding = true);
    try {
      await appStorages.rebuildRecent();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Rebuild failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _rebuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DemoPage(
      title: 'Eviction',
      explainer:
          'The "recent" box is built with maxEntries: '
          '$kRecentMaxEntries and an evictable filter for "$kRecentPrefix" '
          'keys. View more than $kRecentMaxEntries items, then rebuild the '
          'storage: it reopens the box tracking use, moves the live pinned '
          'note store over with rebindAll, then calls evict, which keeps the '
          'most recently used items. The pinned note is never evicted.',
      children: [
        Section(
          title: 'Items',
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 1; i <= _kItemCount; i++)
                  FilterChip(
                    key: Key('recent_item_$i'),
                    label: Text('Item $i'),
                    selected: _viewed.contains(i),
                    // A tap mid-rebuild would bind to the closing box.
                    onSelected: _rebuilding ? null : (_) => _view(i),
                  ),
              ],
            ),
            if (_viewed.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Viewed, oldest first: ${_viewed.join(', ')}'),
            ],
          ],
        ),
        FilledButton.icon(
          key: const Key('rebuild_recent'),
          onPressed: _rebuilding ? null : _rebuild,
          icon: const Icon(Icons.autorenew),
          label: Text(_rebuilding ? 'Rebuilding…' : 'Rebuild storage (evict)'),
        ),
        const SizedBox(height: 16),
        LiveBoxKeys(
          title: '"$kRecentBox" box',
          storage: () => appStorages.recent,
        ),
      ],
    );
  }
}
