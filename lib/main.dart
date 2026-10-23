/// LogisticsLab - one app for the logistics optimisation problems of pyLogisticsLab (desktop, browser, tablet).
library;

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_state.dart';
import 'ui/main_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  final state = await AppState.create();
  runApp(LogisticsLabApp(state: state));
}

class LogisticsLabApp extends StatelessWidget {
  final AppState state;
  const LogisticsLabApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => MaterialApp(
      title: 'LogisticsLab',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: MainScreen(state: state),
    ),
  );
}
