import 'package:flutter/material.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';

import '../stores/rows_store.dart';
import '../widgets/demo_page.dart';

const _kRows = 2000;
const _kWarmUp = 3;
const _kRuns = 20;

class TrustJsonPage extends StatefulWidget {
  const TrustJsonPage({super.key});

  @override
  State<TrustJsonPage> createState() => _TrustJsonPageState();
}

class _TrustJsonPageState extends State<TrustJsonPage> {
  double? _traversedMs;
  double? _trustedMs;
  bool _running = false;

  /// Average time of one change's persistence run: toJson, the traversal
  /// unless trusted, change detection and the hand-off to storage. An
  /// in-memory storage keeps disk time out of the measurement.
  Future<double> _measure({required bool trusted}) async {
    final store = RowsStore(
      trusted: trusted,
      rowCount: _kRows,
      storage: InMemoryStorage(),
    );
    for (var i = 0; i < _kWarmUp; i++) {
      store.bump();
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < _kRuns; i++) {
      store.bump();
    }
    watch.stop();
    store.dispose();
    return watch.elapsedMicroseconds / _kRuns / 1000;
  }

  Future<void> _run() async {
    setState(() => _running = true);
    // Let the button repaint before the measurement holds the UI thread.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final traversed = await _measure(trusted: false);
    final trusted = await _measure(trusted: true);
    if (!mounted) return;
    setState(() {
      _traversedMs = traversed;
      _trustedMs = trusted;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    String ms(double? value) => value == null ? '–' : value.toStringAsFixed(2);
    final traversed = _traversedMs;
    final trusted = _trustedMs;
    return DemoPage(
      title: 'trustToJson',
      explainer: 'A store of $_kRows plain-JSON rows. By default each write '
          'walks and copies the whole map. A store whose toJson already '
          'returns plain JSON can override trustToJson to skip that walk.',
      children: [
        Section(
          title:
              'Milliseconds per write ($_kRuns writes, debug builds are slower)',
          children: [
            StatRow(
              tiles: [
                StatTile(label: 'traversed (default)', value: ms(traversed)),
                StatTile(label: 'trustToJson: true', value: ms(trusted)),
                StatTile(
                  label: 'faster',
                  value: traversed == null || trusted == null || trusted == 0
                      ? '–'
                      : '${(traversed / trusted).toStringAsFixed(1)}×',
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('trust_run'),
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.speed),
              label: Text(_running ? 'Measuring…' : 'Measure'),
            ),
          ],
        ),
      ],
    );
  }
}
