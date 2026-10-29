import 'package:flutter/material.dart';

/// The frame of every feature page: a title, a short explainer, then the
/// page's content in a scrolling column.
class DemoPage extends StatelessWidget {
  const DemoPage({
    super.key,
    required this.title,
    required this.explainer,
    required this.children,
  });

  final String title;
  final String explainer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Card(
            color: scheme.secondaryContainer,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      explainer,
                      style: TextStyle(color: scheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

/// A titled group of content on a feature page.
class Section extends StatelessWidget {
  const Section({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// A big number with a caption under it.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// A row of [StatTile]s sharing the width.
class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.tiles});

  final List<StatTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Row(children: [for (final tile in tiles) Expanded(child: tile)]);
  }
}

/// A storage key and its value, in monospace.
class KeyValueTile extends StatelessWidget {
  const KeyValueTile({
    super.key,
    required this.storageKey,
    required this.value,
    this.trailing,
  });

  final String storageKey;
  final Object? value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = '$value';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(storageKey, style: const TextStyle(fontFamily: 'monospace')),
      subtitle: Text(
        text.length > 120 ? '${text.substring(0, 120)}…' : text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
      trailing: trailing,
    );
  }
}
