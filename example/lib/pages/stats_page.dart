import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import '../app/app_storages.dart';
import '../stores/stats_counter_store.dart';
import '../widgets/demo_page.dart';

const _kChanges = 100;
const _kDelay = Duration(milliseconds: 300);

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  int? _immediateWrites;
  int? _delayedWrites;
  int? _recreateWrites;
  bool _running = false;

  Future<int> _writesDuring(String key, Future<void> Function() work) async {
    final before = appStorages.main.writesOf(key);
    await work();
    // The counting storage records writes in a microtask.
    await Future<void>.delayed(Duration.zero);
    return appStorages.main.writesOf(key) - before;
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final immediate =
        StatsCounterStore(id: 'immediate', persistDelay: Duration.zero);
    final delayed = StatsCounterStore(id: 'delayed', persistDelay: _kDelay);
    await delayed.flush();

    final immediateWrites = await _writesDuring('stats_immediate', () async {
      for (var i = 0; i < _kChanges; i++) {
        immediate.increment();
      }
      await immediate.flush();
    });
    final delayedWrites = await _writesDuring('stats_delayed', () async {
      for (var i = 0; i < _kChanges; i++) {
        delayed.increment();
      }
      await delayed.flush();
    });
    immediate.dispose();
    delayed.dispose();

    // A new instance hydrates the state just written and finds nothing to
    // write back (1.x wrote it again on every construction).
    late StatsCounterStore again;
    final recreateWrites = await _writesDuring('stats_immediate', () async {
      again = StatsCounterStore(id: 'immediate', persistDelay: Duration.zero);
      await again.flush();
    });
    again.dispose();

    if (!mounted) return;
    setState(() {
      _immediateWrites = immediateWrites;
      _delayedWrites = delayedWrites;
      _recreateWrites = recreateWrites;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    String show(int? value) => value == null ? '–' : '$value';
    return DemoPage(
      title: 'Write stats',
      explainer: 'The default box is wrapped in a counting Storage. Run '
          '$_kChanges rapid changes against a store without persistDelay and '
          'one with ${_kDelay.inMilliseconds} ms, then re-create a store.',
      children: [
        Section(
          title: '$_kChanges changes',
          children: [
            StatRow(
              tiles: [
                StatTile(
                    label: 'writes, no delay', value: show(_immediateWrites)),
                StatTile(
                  label: 'writes, ${_kDelay.inMilliseconds} ms delay',
                  value: show(_delayedWrites),
                ),
                StatTile(
                  label: 'writes when re-created',
                  value: show(_recreateWrites),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('stats_run'),
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.play_arrow),
              label: Text(_running ? 'Running…' : 'Run experiment'),
            ),
          ],
        ),
        Section(
          title: 'Every write to the default box',
          children: [
            Observer(
              builder: (_) {
                final storage = appStorages.main;
                final entries = storage.writes.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));
                final bytes = storage.bytes.values.fold(0, (a, b) => a + b);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StatRow(
                      tiles: [
                        StatTile(
                            label: 'writes', value: '${storage.totalWrites}'),
                        StatTile(
                            label: 'KB written',
                            value: (bytes / 1024).toStringAsFixed(1)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final entry in entries)
                      KeyValueTile(
                        storageKey: entry.key,
                        value: '${entry.value} writes, '
                            '${storage.bytes[entry.key] ?? 0} bytes',
                      ),
                  ],
                );
              },
            ),
            TextButton(
              onPressed: appStorages.main.resetStats,
              child: const Text('Reset counters'),
            ),
          ],
        ),
      ],
    );
  }
}
