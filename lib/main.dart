/// LogisticsLab Studio - one app for the logistics optimisation problems of pyLogisticsLab (desktop, browser, tablet).
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_log.dart';
import 'app_state.dart';
import 'help/help.dart';
import 'ui/about_dialog.dart';
import 'ui/file_ops.dart';
import 'ui/help_dialog.dart';
import 'ui/main_screen.dart';
import 'ui/theme.dart';

/// args: the file to open - Windows and Linux pass it when it is opened in the Explorer or the file manager
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  if (kIsWeb) await _loadDefaultFont();
  final state = await AppState.create();
  runApp(
    LogisticsLabApp(
      state: state,
      files: [
        for (final a in args)
          if (!a.startsWith('-')) a,
      ],
    ),
  );
}

/// the browser: Roboto of the app also as the default font of the engine - text without a family (tooltips, outside
/// of the Material of the app) asks for it; the engine would load it from the server, where it is not, and Safari
/// shows nothing (no fallback of the system as in Chrome)
Future<void> _loadDefaultFont() async {
  final fonts = FontLoader('Roboto');
  for (final f in ['Regular', 'Medium', 'Bold']) {
    fonts.addFont(rootBundle.load('assets/fonts/Roboto-$f.ttf'));
  }
  await fonts.load();
}

/// menu of macOS (macos/Runner/AppDelegate.swift): "About LogisticsLab Studio" shows the about dialog of the app
const _menu = MethodChannel('logisticslab/menu');

/// title of the window on macOS (macos/Runner/MainFlutterWindow.swift) - other systems keep the name of the app
const _window = MethodChannel('logisticslab/window');
String? _windowTitle;

void _setWindowTitle(String title) {
  if (kIsWeb || title == _windowTitle) return;
  _windowTitle = title;
  _window.invokeMethod('title', title).catchError((_) => null); // no handler: title unchanged
}

final _navigator = GlobalKey<NavigatorState>();

/// files opened in the Finder on macOS (macos/Runner/AppDelegate.swift): those of the start once the app is shown
/// (ready), later ones at once (open)
const _files = MethodChannel('logisticslab/files');

/// the first of the files - in this window, after the question about unsaved changes
Future<void> _openFiles(AppState state, List<String> paths) async {
  final context = _navigator.currentContext;
  if (paths.isNotEmpty) appLog('open files $paths${context == null ? ': no window' : ''}');
  if (paths.isEmpty || context == null) return;
  await FileOps(context, state).openPath(paths.first);
}

/// the help topics of the language for the search of the help menu of macOS (macos/Runner/AppDelegate.swift)
String? _helpLanguage;

void _sendHelpTopics(AppState state) {
  final language = state.strings.language;
  if (kIsWeb || language == _helpLanguage) return;
  _helpLanguage = language;
  HelpBook.load(language)
      .then(
        (book) => _menu.invokeMethod('helpTopics', {
          // titles of the help menu and of its item in the language of the app
          'menu': state.strings('ui.help.menu'),
          'item': state.strings('ui.help.title'),
          'topics': [
            for (final t in book.topics) {'id': t.id, 'title': t.title, 'text': '${t.title} ${t.keywords} ${t.plain}'},
          ],
        }),
      )
      .catchError((_) => null); // no handler: other systems
}

/// e.g. "brandenburg.llab • - LogisticsLab Studio"
String windowTitle(AppState s) => '${s.fileName ?? s.strings('ui.untitled')}${s.dirty ? ' •' : ''} – $appName';

class LogisticsLabApp extends StatelessWidget {
  final AppState state;
  LogisticsLabApp({super.key, required this.state, List<String> files = const []}) {
    if (!kIsWeb) {
      _files.setMethodCallHandler((call) async {
        if (call.method == 'open') await _openFiles(state, [...(call.arguments as List).cast<String>()]);
      });
      // once the window is shown: the files of the start
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final pending = await _files.invokeListMethod<String>('ready').catchError((_) => null) ?? const <String>[];
        await _openFiles(state, [...files, ...pending]);
      });
    }
    _menu.setMethodCallHandler((call) async {
      final context = _navigator.currentContext;
      if (context == null) return;
      switch (call.method) {
        case 'about':
          await showAbout(context, state);
        // help menu of macOS: a topic of its search, all topics of a search or the help
        case 'help':
          final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
          await showHelp(context, state, topic: args['topic'] as String?, query: args['query'] as String?);
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      _setWindowTitle(windowTitle(state));
      _sendHelpTopics(state);
      return MaterialApp(
        // file - app, a dot for unsaved changes
        title: windowTitle(state),
        navigatorKey: _navigator,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: MainScreen(state: state),
      );
    },
  );
}
