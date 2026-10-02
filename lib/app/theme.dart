import 'package:flutter/material.dart';

// ── Obsidian-inspired palette ──────────────────────────────────────────────
// Dark  : #1e1e2e canvas, #7c6af7 violet accent, #cba6f7 mauve highlight
// Light : #eff1f5 canvas, #7287fd violet accent, #8839ef purple
const _obsidianVioletDark  = Color(0xFF7c6af7);
const _obsidianVioletLight = Color(0xFF7287fd);

ThemeData buildNoterrTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  // Build the colour scheme around Obsidian's signature violet
  final scheme = ColorScheme.fromSeed(
    seedColor: isDark ? _obsidianVioletDark : _obsidianVioletLight,
    brightness: brightness,
    // Override key surfaces to match Obsidian exactly
    surface:               isDark ? const Color(0xFF1e1e2e) : const Color(0xFFeff1f5),
    surfaceContainerLowest:isDark ? const Color(0xFF181825) : const Color(0xFFe6e9ef),
    surfaceContainerLow:   isDark ? const Color(0xFF1e1e2e) : const Color(0xFFeff1f5),
    surfaceContainer:      isDark ? const Color(0xFF24273a) : const Color(0xFFdce0e8),
    surfaceContainerHigh:  isDark ? const Color(0xFF313244) : const Color(0xFFccd0da),
    onSurface:             isDark ? const Color(0xFFcdd6f4) : const Color(0xFF4c4f69),
    onSurfaceVariant:      isDark ? const Color(0xFFa6adc8) : const Color(0xFF5c5f77),
    outline:               isDark ? const Color(0xFF45475a) : const Color(0xFF9ca0b0),
    outlineVariant:        isDark ? const Color(0xFF313244) : const Color(0xFFbcc0cc),
    primary:               isDark ? _obsidianVioletDark  : _obsidianVioletLight,
    onPrimary:             const Color(0xFFFFFFFF),
    secondary:             isDark ? const Color(0xFFcba6f7) : const Color(0xFF8839ef),
    onSecondary:           const Color(0xFFFFFFFF),
    tertiary:              isDark ? const Color(0xFF89b4fa) : const Color(0xFF209fb5),
    error:                 isDark ? const Color(0xFFf38ba8) : const Color(0xFFd20f39),
  );

  final baseText = TextTheme(
    displayLarge:  TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w300, letterSpacing: -1),
    displayMedium: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w300, letterSpacing: -0.5),
    headlineLarge: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
    headlineMedium:TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
    titleLarge:    TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600, fontSize: 18),
    titleMedium:   TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w500, fontSize: 15),
    titleSmall:    TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500, fontSize: 13),
    bodyLarge:     TextStyle(color: scheme.onSurface,        fontSize: 14, height: 1.6),
    bodyMedium:    TextStyle(color: scheme.onSurface,        fontSize: 13, height: 1.55),
    bodySmall:     TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.5),
    labelLarge:    TextStyle(color: scheme.primary, fontWeight: FontWeight.w600, fontSize: 13),
    labelMedium:   TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
    labelSmall:    TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, letterSpacing: 0.5),
  );

  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    // Prefer a clean sans-serif that complements Obsidian's Inter-like look
    fontFamily: 'Segoe UI',
    textTheme: baseText,

    // ── AppBar ──────────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor:  isDark ? const Color(0xFF181825) : const Color(0xFFe6e9ef),
      foregroundColor:  scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: 'Segoe UI',
        color: scheme.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
      actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
      shape: Border(
        bottom: BorderSide(
          color: scheme.outlineVariant,
          width: 1,
        ),
      ),
    ),

    // ── Cards ────────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: scheme.outlineVariant, width: 1),
      ),
    ),

    // ── Inputs ───────────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.55), fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),

    // ── Buttons ──────────────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
      ),
    ),

    // ── FAB ─────────────────────────────────────────────────────────────────
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    // ── Dialogs ──────────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      titleTextStyle: TextStyle(
        fontFamily: 'Segoe UI',
        color: scheme.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),

    // ── Snackbar ─────────────────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? const Color(0xFF313244) : const Color(0xFF4c4f69),
      contentTextStyle: const TextStyle(color: Color(0xFFcdd6f4), fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      actionTextColor: _obsidianVioletDark,
    ),

    // ── ListTile ─────────────────────────────────────────────────────────────
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      subtitleTextStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    ),

    // ── Checkbox ─────────────────────────────────────────────────────────────
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return scheme.primary;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(scheme.onPrimary),
      side: BorderSide(color: scheme.outline, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),

    // ── Divider ──────────────────────────────────────────────────────────────
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),

    // ── BottomSheet ──────────────────────────────────────────────────────────
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? const Color(0xFF24273a) : const Color(0xFFeff1f5),
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      dragHandleColor: scheme.outlineVariant,
    ),

    // ── Switch ───────────────────────────────────────────────────────────────
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? scheme.primary : scheme.outline),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? scheme.primary.withValues(alpha: 0.3)
              : scheme.outlineVariant),
    ),

    // ── Icon ─────────────────────────────────────────────────────────────────
    iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
  );
}
