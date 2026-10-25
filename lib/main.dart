/// LogisticsLab Studio - one app for the logistics optimisation problems of pyLogisticsLab (desktop, browser, tablet).
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_state.dart';
import 'help/help.dart';
import 'ui/about_dialog.dart';
import 'ui/help_dialog.dart';
import 'ui/main_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  final state = await AppState.create();
  runApp(LogisticsLabApp(state: state));
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
  LogisticsLabApp({super.key, required this.state}) {
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
