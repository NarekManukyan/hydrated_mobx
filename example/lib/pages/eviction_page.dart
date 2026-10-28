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

  @override
  void initState() {
    super.initState();
    // Writes the pinned note once, beside the cache entries.
    final pinned = PinnedNoteStore();
    pinned.flush().whenComplete(pinned.dispose);
  }

  /// Opens item [index]'s cache entry, counts a view and closes it again.
  Future<void> _view(int index) async {
    final store = RecentItemStore('item_$index')..view();
    await store.flush();
    store.dispose();
    setState(() => _viewed
      ..remove(index)
      ..add(index));
  }

  Future<void> _rebuild() async {
    setState(() => _rebuilding = true);
    await appStorages.rebuildRecent();
    setState(() => _rebuilding = false);
  }

  @override
  Widget build(BuildContext context) {
    return DemoPage(
      title: 'Eviction',
      explainer: 'The "recent" box is built with maxEntries: '
          '$kRecentMaxEntries and an evictable filter for "$kRecentPrefix" '
          'keys. View more than $kRecentMaxEntries items, then rebuild the '
          'storage: eviction runs at build and keeps the most recently used '
          'ones. The pinned note is never evicted.',
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
                    onSelected: (_) => _view(i),
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
