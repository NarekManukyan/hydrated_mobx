import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';

import '../app/app_observer.dart';
import '../app/app_storages.dart';
import '../stores/failing_stores.dart';
import '../widgets/demo_page.dart';

class ObserverPage extends StatelessWidget {
  const ObserverPage({super.key});

  /// Leaves a value that is not a map under the store's key.
  Future<void> _hydrationError() async {
    await appStorages.main.write(kBrokenToken, 'not a map');
    BrokenStore().dispose();
  }

  /// The store's first persistence run cannot encode its payload.
  void _serializationError() => UnencodableStore().dispose();

  /// The store's storage is closed before its next write.
  Future<void> _closedStorage() async {
    final storage = InMemoryStorage();
    final store = ClosedStorageStore(storage);
    await storage.close();
    store
      ..increment()
      ..dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DemoPage(
      title: 'Observer & errors',
      explainer: 'One HydratedObserver, set at startup, receives the '
          'failures of every store that has no handler of its own, and '
          'hears about migrations. No per-store error callbacks needed.',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              key: const Key('trigger_hydration_error'),
              onPressed: _hydrationError,
              icon: const Icon(Icons.broken_image_outlined),
              label: const Text('Hydration error'),
            ),
            FilledButton.tonalIcon(
              key: const Key('trigger_serialization_error'),
              onPressed: _serializationError,
              icon: const Icon(Icons.data_object),
              label: const Text('Unencodable state'),
            ),
            FilledButton.tonalIcon(
              key: const Key('trigger_closed_storage'),
              onPressed: _closedStorage,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Write to closed storage'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Section(
          title: 'Observer log',
          children: [
            Observer(
              builder: (_) {
                if (appObserver.log.isEmpty) return const Text('(empty)');
                return Column(
                  children: [
                    for (final entry in appObserver.log) _LogTile(entry),
                  ],
                );
              },
            ),
            TextButton(
              onPressed: appObserver.clearLog,
              child: const Text('Clear log'),
            ),
          ],
        ),
      ],
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile(this.entry);

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (entry.kind) {
      LogKind.hydrationError => (
          Icons.error_outline,
          scheme.error,
          'onHydrationError'
        ),
      LogKind.storageError => (
          Icons.warning_amber,
          scheme.tertiary,
          'onStorageError'
        ),
      LogKind.migration => (Icons.upgrade, scheme.primary, 'onMigrate'),
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text('$label · ${entry.token}'),
      subtitle:
          Text(entry.message, maxLines: 3, overflow: TextOverflow.ellipsis),
    );
  }
}
