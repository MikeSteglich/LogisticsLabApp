/// Messages to the user: errors stay until they are closed, notes disappear after a few seconds,
/// a busy dialog blocks the app while a step runs that must not be interrupted (e.g. import).
library;

import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import 'theme.dart';

/// short note at the bottom, e.g. "saved"
void showNote(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
}

/// error - stays until closed, the text can be selected and copied
Future<void> showError(BuildContext context, Strings t, String text) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.error_outline, color: Ui.error),
      title: Text(t('ui.status.error')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(child: SelectableText(text)),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(t('ui.close')))],
    ),
  );
}

/// runs [work] behind a dialog that blocks the app - with [text], e.g. "importing drogma.CLPX …"
Future<T> busy<T>(BuildContext context, String text, Future<T> Function() work) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 16),
            Flexible(child: Text(text)),
          ],
        ),
      ),
    ),
  );
  try {
    return await work();
  } finally {
    navigator.pop();
  }
}
