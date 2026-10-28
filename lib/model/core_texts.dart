import '../i18n/strings.dart';

/// The texts of the computing core in the language of the app - the core writes them in English.
///
/// Warnings of the solution document by their code (warningCodes, parallel to warnings), the messages of the jobs
/// (no solution, time limit, ...) by their wording. Unknown texts stay as they are.

/// the warnings of a solution document
List<String> coreWarnings(Strings t, Map<String, dynamic> document) {
  final texts = [for (final w in (document['warnings'] as List? ?? const [])) '$w'];
  final codes = (document['warningCodes'] as List?)?.cast<Map>();
  if (codes == null || codes.length != texts.length) return texts;
  return [for (final (i, c) in codes.indexed) _warning(t, c.cast<String, dynamic>()) ?? texts[i]];
}

String? _warning(Strings t, Map<String, dynamic> c) {
  final key = 'core.warning.${c['code']}';
  if (!t.has(key)) return null;
  // names of attributes and problem types as in the app
  String named(String prefix, Object? v) => t.has('$prefix$v') ? t('$prefix$v') : '$v';
  return t(key, {
    for (final MapEntry(:key, :value) in c.entries)
      if (key != 'code')
        key: switch (key) {
          'attribute' => named('field.', value),
          'type' => named('module.', value),
          _ => '$value',
        },
  });
}

// messages of the jobs of the core - their wording, its numbers as arguments
final _messages = <(RegExp, String)>[
  (RegExp(r'^solution has been found$', caseSensitive: false), 'core.message.solution'),
  (RegExp(r'^no solution has been found$', caseSensitive: false), 'core.message.noSolution'),
  (RegExp(r'^the solver process does not start$'), 'core.message.noStart'),
  (RegExp(r'^solver process has stopped unexpectedly$'), 'core.message.stopped'),
  (RegExp(r'^time limit exceeded - the problem has been stopped after (?<seconds>[\d.]+)s$'), 'core.message.timeLimit'),
  (
    RegExp(r'^Problem has been cancelled - the status has not been requested for more than (?<seconds>[\d.]+)s$'),
    'core.message.notPolled',
  ),
  (RegExp(r'^Problem has been cancelled$'), 'core.message.cancelled'),
];

/// a message of the core - e.g. the message of a solution without a solution
String coreMessage(Strings t, String message) {
  for (final (pattern, key) in _messages) {
    if (pattern.firstMatch(message.trim()) case final m?) {
      return t(key, {for (final name in m.groupNames) name: m.namedGroup(name)!});
    }
  }
  return message;
}
