/// LogisticsLab Studio - one app for the logistics optimisation problems of pyLogisticsLab (desktop, browser, tablet).
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_state.dart';
import 'ui/about_dialog.dart';
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

/// e.g. "brandenburg.llab • - LogisticsLab Studio"
String windowTitle(AppState s) => '${s.fileName ?? s.strings('ui.untitled')}${s.dirty ? ' •' : ''} – $appName';

class LogisticsLabApp extends StatelessWidget {
  final AppState state;
  LogisticsLabApp({super.key, required this.state}) {
    _menu.setMethodCallHandler((call) async {
      final context = _navigator.currentContext;
      if (call.method == 'about' && context != null) await showAbout(context, state);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      _setWindowTitle(windowTitle(state));
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
