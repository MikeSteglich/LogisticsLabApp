/// Flat, plain look of the design canvas - colours and sizes in one place.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

abstract final class Ui {
  static const background = Color(0xFFF4F5F7);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF7F8FA);
  static const border = Color(0xFFE2E5EA);
  static const inputBorder = Color(0xFFCDD2D9);
  static const text = Color(0xFF1A1D21);
  static const textSecondary = Color(0xFF5B6470);
  static const textMuted = Color(0xFF3B424B);
  static const accent = Color(0xFF1D5FD1);
  static const accentDark = Color(0xFF174BA6);
  static const accentLight = Color(0xFFEAF1FD);
  static const ok = Color(0xFF1F8A4C);
  static const warning = Color(0xFFB4690E);
  static const error = Color(0xFFC0362C);
  static const mapBackground = Color(0xFFE9EDF1);
  static const pale = Color(0xFFA3ABB5); // nodes without a role in the problem
  // edges of the network on the map: petrol - not in the colours of the OSM map (roads grey/white, yellow, orange,
  // red, water light blue, green); blue is for the used edges of a solution, orange for the highlighted one
  static const network = Color(0xFF2F6F73);
  // tours of the vehicles (vrp) - beside the colours of the roles, the network (petrol) and the highlight (orange)
  static const routeColors = [
    Color(0xFF1D5FD1), // blue (accent)
    Color(0xFFC2185B), // magenta
    Color(0xFF6A4C93), // purple
    Color(0xFFB8860B), // dark gold
    Color(0xFF5D4037), // brown
    Color(0xFF283593), // indigo
    Color(0xFFD32F2F), // red
    Color(0xFF00838F), // cyan
  ];
  static const networkSelected = Color(0xFF1B4547); // selected edge of the network
  // colours of the roles on the map: suppliers blue (not the blue of the solution lines), customers green
  static const supplier = Color(0xFF2F6DB5);
  static const supplierDark = Color(0xFF1F4E87);
  static const customer = Color(0xFF3DA672);
  static const customerDark = Color(0xFF2A7A52);
  static const candidate = Color(0xFF7B5CC4); // warehouses, candidates for locations
  static const candidateDark = Color(0xFF5B3FA0);
  // transshipment nodes of a network flow: raspberry - apart from the petrol of the edges and the other roles
  static const transit = Color(0xFFB0256A);
  static const transitDark = Color(0xFF7A1449);
  static const pickup = Color(0xFFE0A030); // pickup and delivery: where the quantities are picked up
  static const pickupDark = Color(0xFFA06A10);

  /// fill and outline of a role - other roles dark grey
  static (Color, Color) roleColors(String role) => switch (role) {
    'supplier' || 'depot' => (supplier, supplierDark),
    'customer' || 'delivery' => (customer, customerDark),
    'pickup' => (pickup, pickupDark),
    'transit' => (transit, transitDark),
    'candidate' => (candidate, candidateDark),
    _ => (textMuted, text),
  };
  static const highlight = Color(0xFFC25A0E); // connection of the solution selected in the table
  static const highlightLight = Color(0xFFFBEEE4);

  static const minTarget = 44.0; // touch targets (tablet)
  static const radius = 6.0;
  static const gap = 12.0;

  static const sectionLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: textSecondary,
  );
  static const title = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: text);
  static const small = TextStyle(fontSize: 12, color: textSecondary);
  static const tabular = [FontFeature.tabularFigures()];
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: Ui.accent, surface: Ui.surface).copyWith(primary: Ui.accent);
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(Ui.radius),
    borderSide: const BorderSide(color: Ui.inputBorder),
  );
  // the browser: the Roboto of the app (pubspec.yaml) - the desktop keeps the font of its system
  final base = Typography.blackMountainView.apply(
    bodyColor: Ui.text,
    displayColor: Ui.text,
    fontFamily: kIsWeb ? 'RobotoWeb' : null,
  );
  // the text in text fields (bodyLarge) and dropdowns (titleMedium): 14 instead of 16 - compact fields
  final textTheme = base.copyWith(
    bodyLarge: base.bodyLarge?.copyWith(fontSize: 14),
    titleMedium: base.titleMedium?.copyWith(fontSize: 14),
  );
  return ThemeData(
    fontFamily: kIsWeb ? 'RobotoWeb' : null,
    colorScheme: scheme,
    scaffoldBackgroundColor: Ui.background,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    dividerTheme: const DividerThemeData(color: Ui.border, space: 1, thickness: 1),
    textTheme: textTheme,
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Ui.surface,
      // compact: some 6 px lower than with 12 - text fields and dropdowns alike
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(borderSide: const BorderSide(color: Ui.accent, width: 1.5)),
      labelStyle: const TextStyle(fontSize: 13, color: Ui.textMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, Ui.minTarget),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ui.radius)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        foregroundColor: Ui.text,
        side: const BorderSide(color: Ui.inputBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ui.radius)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, Ui.minTarget),
        foregroundColor: Ui.text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ui.radius)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Ui.surface,
      selectedColor: Ui.accentLight,
      side: const BorderSide(color: Ui.inputBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      labelStyle: textTheme.labelLarge?.copyWith(fontSize: 13, color: Ui.textMuted, fontWeight: FontWeight.w400),
      showCheckmark: false,
    ),
    menuTheme: const MenuThemeData(
      style: MenuStyle(backgroundColor: WidgetStatePropertyAll(Ui.surface), elevation: WidgetStatePropertyAll(4)),
    ),
    // dark text on a light card - like the hover card of the edges on the map
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 600),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: const TextStyle(fontSize: 12, color: Ui.text, fontFeatures: Ui.tabular),
      decoration: BoxDecoration(
        color: Ui.surface,
        borderRadius: BorderRadius.circular(Ui.radius),
        border: Border.all(color: Ui.border),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
    ),
  );
}
