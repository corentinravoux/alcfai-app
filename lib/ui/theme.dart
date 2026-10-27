import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Design tokens. One dark theme: the app is a frame around terminals.
///
/// Cool ink-slate base (not neutral near-black), one cobalt accent for
/// focus and selection, and three status colours that only ever mean
/// model state (running / queued / offline) or an error.
abstract final class Tok {
  static const bg = Color(0xFF161A22); // terminal + canvas
  static const rail = Color(0xFF1C212B); // sidebar
  static const raised = Color(0xFF242A36); // hover, active tile, tab
  static const line = Color(0xFF2D3442);
  static const text = Color(0xFFE4E7ED);
  static const muted = Color(0xFF959DAB);
  static const faint = Color(0xFF636B7A);
  static const accent = Color(0xFF6F9BEA); // cobalt
  static const running = Color(0xFF7DC49B);
  static const queued = Color(0xFFE0B65E);
  static const danger = Color(0xFFE47F7A);

  static const ui = 'Atkinson';
  static const mono = 'JetBrains Mono';

  static const radius = 6.0; // one radius everywhere: tiles, buttons, dialog
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    surface: Tok.bg,
    primary: Tok.accent,
    onPrimary: Tok.bg,
    secondary: Tok.accent,
    error: Tok.danger,
    onSurface: Tok.text,
    outline: Tok.line,
  );
  final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Tok.radius));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Tok.bg,
    fontFamily: Tok.ui,
    dividerColor: Tok.line,
    textTheme: const TextTheme(
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      bodyMedium: TextStyle(fontSize: 14, height: 1.4),
      bodySmall: TextStyle(fontSize: 12.5, height: 1.35, color: Tok.muted),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ).apply(bodyColor: Tok.text, displayColor: Tok.text),
    dialogTheme: DialogThemeData(backgroundColor: Tok.rail, shape: shape),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: shape, backgroundColor: Tok.accent),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
          shape: shape,
          foregroundColor: Tok.text,
          side: const BorderSide(color: Tok.line)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: shape, foregroundColor: Tok.accent),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Tok.bg,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tok.radius),
          borderSide: const BorderSide(color: Tok.line)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tok.radius),
          borderSide: const BorderSide(color: Tok.line)),
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(color: Tok.raised),
      textStyle: TextStyle(color: Tok.text, fontSize: 12.5),
    ),
  );
}

const terminalTheme = TerminalTheme(
  cursor: Tok.accent,
  selection: Color(0x556F9BEA),
  foreground: Tok.text,
  background: Tok.bg,
  black: Color(0xFF1C212B),
  red: Color(0xFFE47F7A),
  green: Color(0xFF7DC49B),
  yellow: Color(0xFFE0B65E),
  blue: Color(0xFF6F9BEA),
  magenta: Color(0xFFC49BE0),
  cyan: Color(0xFF6CC3C8),
  white: Color(0xFFC9CED8),
  brightBlack: Color(0xFF636B7A),
  brightRed: Color(0xFFF0A09B),
  brightGreen: Color(0xFFA3DDB9),
  brightYellow: Color(0xFFF0D08C),
  brightBlue: Color(0xFF9DBDF3),
  brightMagenta: Color(0xFFDABCF0),
  brightCyan: Color(0xFF98DCDF),
  brightWhite: Color(0xFFF2F4F7),
  searchHitBackground: Color(0xFF3A4252),
  searchHitBackgroundCurrent: Color(0xFF6F9BEA),
  searchHitForeground: Tok.text,
);
