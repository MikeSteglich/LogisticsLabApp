/// Messages to the user: errors stay until they are closed, notes disappear after a few seconds,
/// a busy dialog blocks the app while a step runs that must not be interrupted (e.g. import).
library;

import 'dart:async';

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
///
/// With [cancelLabel] the dialog has a button to give up waiting: the result is null then, a later result or
/// error of [work] is dropped, and [onCancel] runs (e.g. to restart a solver that hangs).
/// The dialog stays at least [minVisible] - a fast step would only flash it.
Future<T?> busy<T>(
  BuildContext context,
  String text,
  Future<T> Function() work, {
  String? cancelLabel,
  VoidCallback? onCancel,
  Duration minVisible = const Duration(milliseconds: 600),
}) {
  final shown = Stopwatch()..start();
  Future<void> rest() async {
    final left = minVisible - shown.elapsed;
    if (left > Duration.zero) await Future.delayed(left);
  }

  final navigator = Navigator.of(context, rootNavigator: true);
  final result = Completer<T?>();
  var open = true;
  void close() {
    if (open) {
      open = false;
      navigator.pop();
    }
  }

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
        actions: [
          if (cancelLabel != null)
            TextButton(
              onPressed: () {
                if (result.isCompleted) return;
                close();
                result.complete(null);
                onCancel?.call();
              },
              child: Text(cancelLabel),
            ),
        ],
      ),
    ),
  );
  work().then(
    (v) async {
      if (result.isCompleted) return; // cancelled - the result is dropped
      await rest();
      if (result.isCompleted) return;
      close();
      result.complete(v);
    },
    onError: (Object e, StackTrace st) async {
      if (result.isCompleted) return;
      await rest();
      if (result.isCompleted) return;
      close();
      result.completeError(e, st);
    },
  );
  return result.future;
}
