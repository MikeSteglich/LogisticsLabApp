/// LogisticsLab - one app for the logistics optimisation problems of pyLogisticsLab (desktop, browser, tablet).
library;

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

/// menu of macOS (macos/Runner/AppDelegate.swift): "About LogisticsLab" shows the about dialog of the app
const _menu = MethodChannel('logisticslab/menu');
final _navigator = GlobalKey<NavigatorState>();

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
    builder: (context, _) => MaterialApp(
      title: 'LogisticsLab',
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: MainScreen(state: state),
    ),
  );
}
