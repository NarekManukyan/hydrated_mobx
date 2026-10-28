import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:hydrated_mobx/hydrated_mobx.dart';

import '../app/app_storages.dart';
import '../stores/session_stores.dart';
import '../widgets/demo_page.dart';
import '../widgets/live_box_keys.dart';

const _kItems = ['Coffee', 'Bread', 'Milk', 'Apples', 'Cheese', 'Tea'];

class NamespacesPage extends StatefulWidget {
  const NamespacesPage({super.key});

  @override
  State<NamespacesPage> createState() => _NamespacesPageState();
}

class _NamespacesPageState extends State<NamespacesPage> {
  late CartStore _cart = CartStore(appStorages.session);
  late DraftStore _draft = DraftStore(appStorages.session);
  final _prefs = AccountPrefsStore(appStorages.account)..countVisit();
  late final _draftText = TextEditingController(text: _draft.text);

  @override
  void dispose() {
    _cart.dispose();
    _draft.dispose();
    _prefs.dispose();
    _draftText.dispose();
    super.dispose();
  }

  /// Wipes the whole session box. Its stores stop persisting first, so
  /// none writes its state back; fresh ones start empty.
  Future<void> _signOut() async {
    await HydratedMobX.clearAll(storage: appStorages.session);
    _cart.dispose();
    _draft.dispose();
    if (!mounted) return;
    setState(() {
      _cart = CartStore(appStorages.session);
      _draft = DraftStore(appStorages.session);
      _draftText.text = _draft.text;
    });
  }

  /// Deletes only the `draft_` keys; the cart is untouched.
  Future<void> _clearDrafts() async {
    await HydratedMobX.clearAll(
      storage: appStorages.session,
      where: (token) => token.startsWith(kDraftPrefix),
    );
    _draft.dispose();
    if (!mounted) return;
    setState(() {
      _draft = DraftStore(appStorages.session);
      _draftText.text = _draft.text;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DemoPage(
      title: 'Namespaces',
      explainer:
          'Two boxes: "session" (cart, draft) and "account" '
          '(preferences). Each store is bound with storage:. Signing out '
          'clears one box in a single call; the other is never touched.',
      children: [
        Section(
          title: 'Session box: cart',
          children: [
            Observer(
              builder: (_) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in _cart.items) Chip(label: Text(item)),
                  ActionChip(
                    key: const Key('cart_add'),
                    avatar: const Icon(Icons.add),
                    label: const Text('Add'),
                    onPressed: () =>
                        _cart.add(_kItems[_cart.items.length % _kItems.length]),
                  ),
                ],
              ),
            ),
          ],
        ),
        Section(
          title: 'Session box: draft',
          children: [
            TextField(
              key: const Key('draft_field'),
              controller: _draftText,
              onChanged: _draft.setText,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Type a message draft…',
              ),
            ),
          ],
        ),
        Section(
          title: 'Account box: preferences',
          children: [
            Observer(
              builder: (_) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Compact mode'),
                subtitle: Text('Page visits: ${_prefs.visits}'),
                value: _prefs.compactMode,
                onChanged: (_) => _prefs.toggleCompact(),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('sign_out'),
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Sign out (clear session)'),
            ),
            OutlinedButton.icon(
              key: const Key('clear_drafts'),
              onPressed: _clearDrafts,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Clear only drafts'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LiveBoxKeys(
          title: '"$kSessionBox" box',
          storage: () => appStorages.session,
        ),
        LiveBoxKeys(
          title: '"$kAccountBox" box',
          storage: () => appStorages.account,
        ),
      ],
    );
  }
}
