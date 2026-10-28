import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import '../app/app_storages.dart';
import '../stores/vault_note_store.dart';
import '../widgets/demo_page.dart';

class EncryptionPage extends StatefulWidget {
  const EncryptionPage({super.key});

  @override
  State<EncryptionPage> createState() => _EncryptionPageState();
}

class _EncryptionPageState extends State<EncryptionPage> {
  final _store = VaultNoteStore();
  late final _text = TextEditingController(text: _store.text);
  String? _check;

  @override
  void dispose() {
    _store.dispose();
    _text.dispose();
    super.dispose();
  }

  /// Looks for the note's plain text in the vault's file on disk.
  Future<void> _checkDisk() async {
    await _store.flush();
    final dir = appStorages.directory;
    if (dir == null || _store.text.isEmpty) return;
    final file = File('$dir/$kVaultBox.hive');
    final bytes = await file.readAsBytes();
    final needle = utf8.encode(_store.text);
    final found = _indexOf(bytes, needle) >= 0;
    setState(() {
      _check = found
          ? 'Found the note as plain text in $kVaultBox.hive'
          : 'The note is not in $kVaultBox.hive as plain text '
              '(${bytes.length} bytes, AES-256 encrypted)';
    });
  }

  static int _indexOf(List<int> haystack, List<int> needle) {
    outer:
    for (var i = 0; i <= haystack.length - needle.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    return DemoPage(
      title: 'Encryption',
      explainer: 'The "vault" box is built with a HydratedAesCipher, so '
          'its file on disk is AES-256 encrypted. Stores read and write it '
          'like any other box.',
      children: [
        Section(
          title: 'Secret note',
          children: [
            TextField(
              key: const Key('vault_field'),
              controller: _text,
              onChanged: _store.setText,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Type something secret…',
              ),
            ),
            const SizedBox(height: 8),
            Observer(
              builder: (_) => Text('${_store.text.length} characters stored'),
            ),
          ],
        ),
        FilledButton.icon(
          key: const Key('vault_check'),
          onPressed: _checkDisk,
          icon: const Icon(Icons.search),
          label: const Text('Search the file for the note'),
        ),
        if (_check case final check?) ...[
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock),
              title: Text(check),
            ),
          ),
        ],
      ],
    );
  }
}
