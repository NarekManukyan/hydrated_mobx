import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import '../app/app_storages.dart';
import '../stores/counter_store.dart';
import '../widgets/demo_page.dart';

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  final _store = CounterStore();

  @override
  void dispose() {
    // Starts the write persistDelay is still holding back, then stops.
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DemoPage(
      title: 'Counter',
      explainer:
          'A store that persists itself. Tap fast: changes within '
          '${kCounterPersistDelay.inMilliseconds} ms are written once. '
          'Kill the app and reopen it — the count is still here.',
      children: [
        Section(
          title: 'Count',
          children: [
            Observer(
              builder: (_) => Text(
                '${_store.count}',
                key: const Key('counter_value'),
                textAlign: TextAlign.center,
                style: theme.textTheme.displayLarge,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  key: const Key('counter_decrement'),
                  onPressed: _store.decrement,
                  icon: const Icon(Icons.remove),
                ),
                const SizedBox(width: 24),
                IconButton.filled(
                  key: const Key('counter_increment'),
                  onPressed: _store.increment,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
        Section(
          title: 'Disk writes of "counter"',
          children: [
            Observer(
              builder: (_) {
                // Re-read whenever a write is counted, so the disk value
                // visibly trails the count while persistDelay holds it back.
                final writes = appStorages.main.writesOf('counter');
                final stored = appStorages.main.read('counter');
                return StatRow(
                  tiles: [
                    StatTile(
                      label: 'on disk',
                      value: stored is Map ? '${stored['count']}' : '–',
                    ),
                    StatTile(label: 'writes so far', value: '$writes'),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  key: const Key('counter_flush'),
                  onPressed: _store.flush,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Flush now'),
                ),
                OutlinedButton.icon(
                  onPressed: _store.reset,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
