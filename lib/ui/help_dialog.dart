/// Help window: search field, the topics found with a snippet, the text of the chosen topic.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../help/help.dart';
import 'theme.dart';

/// [topic]: the topic shown first, [query]: the search (e.g. from the help menu of macOS)
Future<void> showHelp(BuildContext context, AppState state, {String? topic, String? query}) async {
  final book = await HelpBook.load(state.strings.language);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (c) => _HelpDialog(state: state, book: book, topic: topic, query: query),
  );
}

class _HelpDialog extends StatefulWidget {
  final AppState state;
  final HelpBook book;
  final String? topic;
  final String? query;
  const _HelpDialog({required this.state, required this.book, this.topic, this.query});

  @override
  State<_HelpDialog> createState() => _HelpDialogState();
}

class _HelpDialogState extends State<_HelpDialog> {
  late final _search = TextEditingController(text: widget.query ?? '');
  late String _topic;

  @override
  void initState() {
    super.initState();
    final hits = widget.book.search(_search.text);
    _topic = widget.topic ?? (hits.isNotEmpty ? hits.first.topic.id : widget.book.topics.first.id);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.state.strings;
    final hits = widget.book.search(_search.text);
    final topic = widget.book.topic(_topic) ?? widget.book.topics.first;

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          autofocus: true,
          decoration: InputDecoration(
            hintText: t('ui.help.search'),
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
          ),
          onChanged: (_) => setState(() {
            final found = widget.book.search(_search.text);
            if (found.isNotEmpty && !found.any((h) => h.topic.id == _topic)) _topic = found.first.topic.id;
          }),
          onSubmitted: (_) {
            if (hits.isNotEmpty) setState(() => _topic = hits.first.topic.id);
          },
        ),
        const SizedBox(height: 8),
        Expanded(
          child: hits.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(t('ui.help.none'), style: const TextStyle(fontSize: 13, color: Ui.textSecondary)),
                )
              : ListView(
                  children: [
                    for (final h in hits)
                      Material(
                        color: h.topic.id == _topic ? Ui.accentLight : Colors.transparent,
                        borderRadius: BorderRadius.circular(Ui.radius),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(Ui.radius),
                          onTap: () => setState(() => _topic = h.topic.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  h.topic.title,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: h.topic.id == _topic ? Ui.accentDark : Ui.text,
                                  ),
                                ),
                                if (h.snippet.isNotEmpty)
                                  Text(
                                    h.snippet,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, color: Ui.textMuted),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
    final text = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(topic.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ..._body(topic.body),
        ],
      ),
    );

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.help_outline, size: 20, color: Ui.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t('ui.help.title'), style: Ui.title)),
                  IconButton(
                    tooltip: t('ui.close'),
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => c.maxWidth < 600
                      // narrow: the topics above the text
                      ? Column(
                          children: [
                            SizedBox(height: 220, child: list),
                            const Divider(height: 20),
                            Expanded(child: text),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 300, child: list),
                            const VerticalDivider(width: 32),
                            Expanded(child: text),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// paragraphs and "- " lists, **bold** inside a line
  List<Widget> _body(String body) {
    const style = TextStyle(fontSize: 14, height: 1.45, color: Ui.text);
    TextSpan rich(String line) {
      final parts = line.split('**');
      return TextSpan(
        style: style,
        children: [
          for (final (i, p) in parts.indexed)
            TextSpan(
              text: p,
              style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w600) : null,
            ),
        ],
      );
    }

    return [
      for (final paragraph in body.split('\n\n'))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in paragraph.split('\n'))
                if (line.startsWith('- '))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(width: 16, child: Text('•', style: style)),
                        Expanded(child: SelectableText.rich(rich(line.substring(2)))),
                      ],
                    ),
                  )
                else
                  SelectableText.rich(rich(line)),
            ],
          ),
        ),
    ];
  }
}
