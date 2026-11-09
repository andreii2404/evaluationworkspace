import 'package:flutter/material.dart';

const ink = Color(0xFF17283F);
const teal = Color(0xFF0F766E);
const canvas = Color(0xFFF6F8FA);
const muted = Color(0xFF475467);
const line = Color(0xFFD0D5DD);
const mint = Color(0xFFD9F3EE);

ThemeData evalinkTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: teal).copyWith(
    primary: teal,
    onPrimary: Colors.white,
    primaryContainer: mint,
    onPrimaryContainer: const Color(0xFF084E49),
    surface: Colors.white,
    onSurface: ink,
    onSurfaceVariant: muted,
    outline: muted,
    outlineVariant: line,
  );
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(12));
  final theme = ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: canvas,
    fontFamily: 'Arial',
    dividerColor: line,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: border,
      enabledBorder: border.copyWith(
        borderSide: const BorderSide(color: muted),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
  final typography = theme.typography;
  return theme.copyWith(
    typography: typography.copyWith(
      englishLike: typography.englishLike.apply(fontSizeDelta: -2),
      dense: typography.dense.apply(fontSizeDelta: -2),
      tall: typography.tall.apply(fontSizeDelta: -2),
    ),
  );
}
