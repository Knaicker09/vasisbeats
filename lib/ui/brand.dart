import 'package:flutter/material.dart';

/// Dark neon design tokens: deep indigo space, cyan and violet neon
/// outlines with glow, electric-blue → violet gradients, and pink / amber /
/// green accents for highlights and status. The app is dark-only.
class Brand {
  Brand._();

  // Backgrounds (darkest → lightest)
  static const bg = Color(0xFF07051A); // scaffold
  static const bgDeep = Color(0xFF0B0724); // chrome bars
  static const surface = Color(0xFF120D2E); // cards, inputs, dialogs
  static const surfaceRaised = Color(0xFF1B1542); // headers, hovered rows
  static const border = Color(0xFF2E2760);
  static const borderStrong = Color(0xFF443B85);

  // Neon accents
  static const cyan = Color(0xFF22D3EE); // primary
  static const cyanBright = Color(0xFF67E8F9);
  static const violet = Color(0xFFA855F7); // secondary
  static const violetDeep = Color(0xFF7C3AED);
  static const blue = Color(0xFF3B82F6); // electric blue
  static const pink = Color(0xFFF472B6);
  static const amber = Color(0xFFFBBF24);
  static const green = Color(0xFF34D399);
  static const red = Color(0xFFF43F5E);

  // Text
  static const text = Color(0xFFF5F3FF);
  static const textSecondary = Color(0xFFC9C3EA);
  static const textMuted = Color(0xFF8C85B8);
  static const textFaint = Color(0xFF5E5890);

  // Status
  static const error = red;
  static const errorText = Color(0xFFFDA4AF);
  static const success = green;
  static const successText = Color(0xFF6EE7B7);
  static const warning = amber;
  static const warningText = Color(0xFFFDE68A);

  // Shape
  static const radius = 12.0; // buttons, inputs
  static const cardRadius = 18.0;
  static const authCardRadius = 24.0;
  static const pill = 999.0;

  /// Primary CTA: electric blue → violet (the "rythm" wordmark gradient).
  static const primaryGradient = LinearGradient(colors: [cyan, blue, violet], stops: [0, 0.45, 1]);
  static const primaryGradientHover =
      LinearGradient(colors: [cyanBright, Color(0xFF60A5FA), Color(0xFFC084FC)], stops: [0, 0.45, 1]);

  /// Headline text gradient.
  static const textGradient = LinearGradient(colors: [cyanBright, Color(0xFF818CF8), violet]);

  static const chromeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xF20B0724), Color(0xE6100A30)],
  );

  /// A neon glow in [color]: a tight bright halo plus a wide soft one.
  static List<BoxShadow> glow(Color color, [double strength = 1]) => [
        BoxShadow(color: color.withValues(alpha: 0.45 * strength), blurRadius: 12 * strength, spreadRadius: -2),
        BoxShadow(color: color.withValues(alpha: 0.25 * strength), blurRadius: 32 * strength, spreadRadius: -4),
      ];

  static const cardShadow = [
    BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 12), spreadRadius: -8),
  ];
}

/// Nunito (body text), weight set through the variable font's `wght` axis
/// so every weight renders correctly from the single bundled font file.
TextStyle nunito(double size, int weight, {Color? color, double? height, double? spacing}) =>
    _variable('Nunito', size, weight, color, height, spacing);

/// Sora (display: headings, labels, numbers), same variable-weight handling.
TextStyle sora(double size, int weight, {Color? color, double? height, double? spacing}) =>
    _variable('Sora', size, weight, color, height, spacing);

TextStyle _variable(String family, double size, int weight, Color? color, double? height, double? spacing) {
  return TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: FontWeight.values[(weight ~/ 100) - 1],
    fontVariations: [FontVariation('wght', weight.toDouble())],
    color: color,
    height: height,
    letterSpacing: spacing,
  );
}

class AppTheme {
  AppTheme._();

  static TextTheme get _textTheme => TextTheme(
        displayLarge: sora(48, 700, color: Brand.text, height: 1.1),
        displayMedium: sora(36, 700, color: Brand.text, height: 1.15),
        headlineLarge: sora(34, 700, color: Brand.text),
        headlineMedium: sora(28, 700, color: Brand.text),
        headlineSmall: sora(22, 700, color: Brand.text),
        titleLarge: sora(19, 600, color: Brand.text),
        titleMedium: nunito(17, 700, color: Brand.text),
        titleSmall: nunito(15, 700, color: Brand.text),
        bodyLarge: nunito(16, 400, color: Brand.textSecondary),
        bodyMedium: nunito(14, 400, color: Brand.textSecondary),
        bodySmall: nunito(12, 400, color: Brand.textMuted),
        labelLarge: sora(13, 600, color: Brand.textSecondary, spacing: 0.4),
        labelMedium: nunito(12, 600, color: Brand.textMuted),
        labelSmall: nunito(11, 600, color: Brand.textMuted),
      );

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(seedColor: Brand.violet, brightness: Brightness.dark).copyWith(
      primary: Brand.cyan,
      onPrimary: Brand.bg,
      primaryContainer: Brand.surfaceRaised,
      onPrimaryContainer: Brand.cyanBright,
      secondary: Brand.violet,
      onSecondary: Colors.white,
      tertiary: Brand.pink,
      onTertiary: Brand.bg,
      surface: Brand.surface,
      onSurface: Brand.text,
      onSurfaceVariant: Brand.textSecondary,
      surfaceContainerLowest: Brand.bg,
      surfaceContainerLow: Brand.surface,
      surfaceContainer: Brand.surface,
      surfaceContainerHigh: Brand.surfaceRaised,
      surfaceContainerHighest: Brand.surfaceRaised,
      error: Brand.red,
      onError: Colors.white,
      outline: Brand.borderStrong,
      outlineVariant: Brand.border,
    );

    OutlineInputBorder border(Color color, [double width = 1.5]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.radius),
          borderSide: BorderSide(color: color, width: width),
        );

    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.radius));

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Nunito',
      colorScheme: scheme,
      scaffoldBackgroundColor: Brand.bg,
      canvasColor: Brand.surface,
      textTheme: _textTheme,
      primaryTextTheme: _textTheme,
      dividerColor: Brand.border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Brand.bg.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: nunito(14, 600, color: Brand.textMuted),
        floatingLabelStyle: nunito(14, 700, color: Brand.cyan),
        hintStyle: nunito(14, 400, color: Brand.textFaint),
        errorStyle: nunito(13, 500, color: Brand.errorText),
        prefixIconColor: Brand.textMuted,
        suffixIconColor: Brand.textMuted,
        border: border(Brand.border),
        enabledBorder: border(Brand.border),
        focusedBorder: border(Brand.cyan, 2),
        errorBorder: border(Brand.red.withValues(alpha: 0.7)),
        focusedErrorBorder: border(Brand.red, 2),
        disabledBorder: border(Brand.border, 1),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Brand.cyan,
          foregroundColor: Brand.bg,
          disabledBackgroundColor: Brand.surfaceRaised,
          disabledForegroundColor: Brand.textFaint,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: buttonShape,
          textStyle: sora(14, 700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Brand.surfaceRaised,
          foregroundColor: Brand.text,
          disabledBackgroundColor: Brand.surface,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          shape: buttonShape,
          elevation: 0,
          textStyle: sora(13, 600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Brand.text,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          side: const BorderSide(color: Brand.borderStrong, width: 1.5),
          shape: buttonShape,
          textStyle: sora(13, 600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Brand.cyan,
          textStyle: nunito(14, 700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: Brand.textSecondary),
      ),
      iconTheme: const IconThemeData(color: Brand.textSecondary),
      cardTheme: CardThemeData(
        color: Brand.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.cardRadius),
          side: const BorderSide(color: Brand.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Brand.surface,
        selectedColor: Brand.cyan.withValues(alpha: 0.18),
        secondarySelectedColor: Brand.cyan.withValues(alpha: 0.18),
        side: WidgetStateBorderSide.resolveWith((s) => BorderSide(
              color: s.contains(WidgetState.selected) ? Brand.cyan : Brand.border,
              width: 1.5,
            )),
        labelStyle: sora(12, 600, color: Brand.textSecondary),
        secondaryLabelStyle: sora(12, 700, color: Brand.cyanBright),
        checkmarkColor: Brand.cyanBright,
        iconTheme: const IconThemeData(color: Brand.textSecondary, size: 16),
        shape: const StadiumBorder(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Brand.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.cardRadius),
          side: const BorderSide(color: Brand.borderStrong),
        ),
        titleTextStyle: sora(18, 700, color: Brand.text),
        contentTextStyle: nunito(14, 400, color: Brand.textSecondary),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Brand.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: Brand.borderStrong,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Brand.authCardRadius))),
      ),
      popupMenuTheme: const PopupMenuThemeData(color: Brand.surfaceRaised, surfaceTintColor: Colors.transparent),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Brand.surfaceRaised,
        contentTextStyle: nunito(14, 600, color: Brand.text),
        actionTextColor: Brand.cyan,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.radius),
          side: BorderSide(color: Brand.cyan.withValues(alpha: 0.5)),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: Brand.cyan,
        inactiveTrackColor: Brand.border,
        thumbColor: Colors.white,
        overlayColor: Brand.cyan.withValues(alpha: 0.16),
        trackHeight: 4,
        valueIndicatorColor: Brand.surfaceRaised,
        valueIndicatorTextStyle: sora(12, 700, color: Brand.cyanBright),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9, elevation: 4),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Brand.cyan,
        linearTrackColor: Brand.border,
        circularTrackColor: Colors.transparent,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Brand.cyan : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Brand.bg),
        side: const BorderSide(color: Brand.borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Brand.cyan : Brand.textMuted,
        ),
      ),
      dividerTheme: const DividerThemeData(color: Brand.border, space: 1),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: Brand.cyan,
        selectionColor: Brand.cyan.withValues(alpha: 0.3),
        selectionHandleColor: Brand.cyan,
      ),
      listTileTheme: const ListTileThemeData(iconColor: Brand.cyan, textColor: Brand.text),
      expansionTileTheme: const ExpansionTileThemeData(
        iconColor: Brand.cyan,
        collapsedIconColor: Brand.textMuted,
        textColor: Brand.text,
        collapsedTextColor: Brand.text,
        shape: Border(),
        collapsedShape: Border(),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(textStyle: nunito(14, 600, color: Brand.text)),
    );
  }
}
