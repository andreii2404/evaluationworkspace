import 'package:flutter/material.dart';

const ink = Color(0xFF17283F);
const teal = Color(0xFF0F766E);
const canvas = Color(0xFFF6F8FA);
const muted = Color(0xFF475467);
const line = Color(0xFFD0D5DD);
const mint = Color(0xFFD9F3EE);

const workshopNight = Color(0xFF111214);
const workshopSurface = Color(0xFF1B1D21);
const workshopBlue = Color(0xFF0466C8);
const workshopIce = Color(0xFFB9D9FF);
const workshopText = Color(0xFFF2F3F5);
const workshopMuted = Color(0xFFB7BBC3);
const workshopEdge = Color(0x35E3E7EF);

ThemeData workshopTheme(ThemeData base) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: workshopEdge),
  );
  return base.copyWith(
    canvasColor: workshopSurface,
    scaffoldBackgroundColor: workshopNight,
    iconTheme: base.iconTheme.copyWith(color: workshopMuted),
    colorScheme: const ColorScheme.dark(
      primary: workshopIce,
      onPrimary: workshopNight,
      primaryContainer: Color(0xFF28384D),
      onPrimaryContainer: workshopText,
      secondary: workshopIce,
      secondaryContainer: Color(0xFF2D3036),
      onSecondaryContainer: workshopText,
      surface: workshopSurface,
      onSurface: workshopText,
      onSurfaceVariant: workshopMuted,
      outline: Color(0xFF818690),
      outlineVariant: workshopEdge,
      surfaceContainerHighest: Color(0xFF2C2E33),
    ),
    textTheme: base.textTheme.apply(
      fontFamily: 'Manrope',
      bodyColor: workshopText,
      displayColor: workshopText,
    ),
    dividerColor: workshopEdge,
    hoverColor: const Color(0x16FFFFFF),
    focusColor: const Color(0x27FFFFFF),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: workshopNight,
      hoverColor: const Color(0x16FFFFFF),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: workshopIce, width: 1.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: workshopSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: workshopEdge),
      ),
    ),
  );
}

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
