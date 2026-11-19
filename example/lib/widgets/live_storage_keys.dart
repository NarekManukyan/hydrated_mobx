import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';

import 'demo_page.dart';

const _kRefresh = Duration(milliseconds: 500);

/// The keys a storage holds, and their values unless [showValues] is off,
/// re-read twice a second so writes, deletes and evictions show up as they
/// happen.
class LiveStorageKeys extends StatefulWidget {
  const LiveStorageKeys({
    super.key,
    required this.title,
    required this.storage,
    this.onDelete,
    this.showValues = true,
  });

  final String title;

  /// Read on every refresh: a box can be closed and rebuilt meanwhile.
  final Storage Function() storage;

  /// Shows a delete button per key when set; it deletes the key's whole
  /// token, state and version.
  final void Function(String key)? onDelete;

  /// Whether to read and show each value. Off for storages of large state,
  /// where reading every value twice a second would decode all of it.
  final bool showValues;

  @override
  State<LiveStorageKeys> createState() => _LiveStorageKeysState();
}

class _LiveStorageKeysState extends State<LiveStorageKeys> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_kRefresh, (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storage = widget.storage();
    List<String> keys;
    try {
      keys = storage.keys.toList()..sort();
    } on StorageClosedException {
      return Section(title: widget.title, children: const [Text('(closed)')]);
    }
    return Section(
      title: '${widget.title} · ${keys.length} keys',
      children: [
        if (keys.isEmpty) const Text('(empty)'),
        for (final key in keys)
          KeyValueTile(
            storageKey: key,
            value: widget.showValues ? storage.read(key) : '(not read)',
            trailing: widget.onDelete == null
                ? null
                : IconButton(
                    tooltip:
                        'Delete ${HydratedMobX.tokenOfKey(key)} '
                        '(state and version)',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => widget.onDelete!(key),
                  ),
          ),
      ],
    );
  }
}
