import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';
import 'package:hydrated_mobx_example/app/app_storages.dart';
import 'package:hydrated_mobx_example/main.dart';

void main() {
  setUp(() {
    appStorages = AppStorages.inMemory();
    HydratedMobX.storage = appStorages.main;
  });

  testWidgets('lists every demo', (tester) async {
    await tester.pumpWidget(const HydratedMobXExampleApp());

    expect(find.text('Counter'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('demo_large')), 200);
    expect(find.byKey(const Key('demo_large')), findsOneWidget);
  });

  testWidgets('the counter persists its count', (tester) async {
    await tester.pumpWidget(const HydratedMobXExampleApp());
    await tester.tap(find.byKey(const Key('demo_counter')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('counter_increment')));
    await tester.tap(find.byKey(const Key('counter_increment')));
    await tester.pump();
    expect(find.text('2'), findsWidgets);

    await tester.tap(find.byKey(const Key('counter_flush')));
    await tester.pump();
    expect(appStorages.main.read('counter'), {'count': 2});
  });

  testWidgets('every demo page opens', (tester) async {
    const ids = [
      'counter',
      'keyed',
      'stats',
      'namespaces',
      'migration',
      'eviction',
      'observer',
      'inspector',
      'encryption',
      'trust',
      'large',
    ];
    await tester.pumpWidget(const HydratedMobXExampleApp());
    for (final id in ids) {
      final tile = find.byKey(Key('demo_$id'));
      await tester.scrollUntilVisible(tile, 200);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: id);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('large notes move from the box to files', (tester) async {
    await tester.pumpWidget(const HydratedMobXExampleApp());
    final tile = find.byKey(const Key('demo_large'));
    await tester.scrollUntilVisible(tile, 200);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('large_add')));
    await tester.pumpAndSettle();
    expect(find.text('In the box: 10 · in files: 0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('large_move')));
    await tester.pumpAndSettle();
    expect(find.text('In the box: 0 · in files: 10'), findsOneWidget);

    await tester.tap(find.byKey(const Key('large_open')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1000 lines'), findsOneWidget);
  });
}
