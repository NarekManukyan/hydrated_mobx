import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import '../stores/keyed_counter_store.dart';
import '../widgets/demo_page.dart';

const _kFruits = ['apples', 'pears', 'plums'];

class KeyedPage extends StatefulWidget {
  const KeyedPage({super.key});

  @override
  State<KeyedPage> createState() => _KeyedPageState();
}

class _KeyedPageState extends State<KeyedPage> {
  final _stores = {for (final id in _kFruits) id: KeyedCounterStore(id)};

  @override
  void dispose() {
    for (final store in _stores.values) {
      store.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DemoPage(
      title: 'Keyed instances',
      explainer:
          'Three instances of one store type. Passing storeId gives '
          'each its own key, so their states never mix.',
      children: [
        for (final MapEntry(key: id, value: store) in _stores.entries)
          Card(
            child: ListTile(
              key: Key('keyed_$id'),
              title: Text(id),
              subtitle: Text(
                store.storageToken,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: store.decrement,
                    icon: const Icon(Icons.remove),
                  ),
                  Observer(
                    builder: (_) => SizedBox(
                      width: 40,
                      child: Text(
                        '${store.count}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: store.increment,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
