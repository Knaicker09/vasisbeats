import 'package:flutter/material.dart';

/// Design tokens taken from the Vasis Studio website's real Tailwind classes
/// (not the unused shadcn defaults in its globals.css):
///  * public/auth pages: white + purple, gradient primary buttons, 8px
///    controls, 16px auth cards, on a flat #d0d0d0 backdrop;
///  * student/admin portal: deep-navy chrome, translucent "glass" tiles,
///    orange navigation accents, over the piano-keys background.
class Brand {
  Brand._();

  // Purples
  static const purple = Color(0xFF7618C0); // primary buttons, focus, active
  static const purpleLight = Color(0xFFAD46FF); // gradient start, links
  static const purpleHover = Color(0xFF9A3EE6);
  static const purpleDark = Color(0xFF6A1BB3);
  static const purple500 = Color(0xFFA855F7); // marketing accent
  static const purple50 = Color(0xFFFAF5FF);
  static const purple100 = Color(0xFFF3E8FF); // focus halo
  static const purple200 = Color(0xFFE9D5FF);
  static const purple300 = Color(0xFFD8B4FE);

  // Portal chrome
  static const orange = Color(0xFFEA580C); // active nav, portal actions
  static const orangeBright = Color(0xFFFE9A00);
  static const navy = Color(0xFF130432);

  // Neutrals
  static const gray50 = Color(0xFFF9FAFB);
  static const gray100 = Color(0xFFF3F4F6);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray300 = Color(0xFFD1D5DB);
  static const gray400 = Color(0xFF9CA3AF);
  static const gray500 = Color(0xFF6B7280);
  static const gray600 = Color(0xFF4B5563);
  static const gray700 = Color(0xFF374151);
  static const gray900 = Color(0xFF111827);
  static const authBackdrop = Color(0xFFD0D0D0);

  // Status
  static const error = Color(0xFFDC2626);
  static const errorBg = Color(0xFFFEF2F2);
  static const errorBorder = Color(0xFFFECACA);
  static const success = Color(0xFF16A34A);
  static const successBg = Color(0xFFF0FDF4);
  static const successBorder = Color(0xFFBBF7D0);
  static const successText = Color(0xFF15803D);
  static const warning = Color(0xFFD97706);
  static const warningBg = Color(0xFFFFFBEB);

  // Shape
  static const radius = 8.0; // buttons, inputs
  static const cardRadius = 12.0;
  static const authCardRadius = 16.0;
  static const pill = 999.0;

  static const primaryGradient = LinearGradient(colors: [purpleLight, purple]);
  static const primaryGradientHover = LinearGradient(colors: [purpleHover, purpleDark]);

  static const chromeGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [Color(0xFF130432), Color(0xFF040732), Color(0xFF250432), Color(0xFF0A0432)],
    stops: [0.0, 0.38, 0.61, 1.0],
  );

  /// The portal's translucent terracotta/red/green tile.
  static const glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x80C95344), Color(0x667F1D1D), Color(0x4D166534)],
  );

  static const cardShadow = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 4), spreadRadius: -1),
    BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 2), spreadRadius: -2),
  ];
  static const authShadow = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 25, offset: Offset(0, 20), spreadRadius: -5),
    BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 8), spreadRadius: -6),
  ];
}

/// Nunito, weight set through the variable font's `wght` axis so every
/// weight renders correctly from the single bundled font file.
TextStyle nunito(double size, int weight, {Color? color, double? height, double? spacing}) {
  return TextStyle(
    fontFamily: 'Nunito',
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
        displayLarge: nunito(48, 700, color: Brand.gray900, height: 1.1),
        displayMedium: nunito(36, 700, color: Brand.gray900, height: 1.15),
        headlineLarge: nunito(36, 700, color: Brand.gray900),
        headlineMedium: nunito(30, 700, color: Brand.gray900),
        headlineSmall: nunito(24, 700, color: Brand.gray900),
        titleLarge: nunito(20, 600, color: Brand.gray900),
        titleMedium: nunito(18, 600, color: Brand.gray900),
        titleSmall: nunito(16, 600, color: Brand.gray900),
        bodyLarge: nunito(16, 400, color: Brand.gray700),
        bodyMedium: nunito(14, 400, color: Brand.gray700),
        bodySmall: nunito(12, 400, color: Brand.gray500),
        labelLarge: nunito(14, 600, color: Brand.gray700),
        labelMedium: nunito(12, 500, color: Brand.gray600),
        labelSmall: nunito(11, 500, color: Brand.gray500),
      );

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: Brand.purple).copyWith(
      primary: Brand.purple,
      onPrimary: Colors.white,
      primaryContainer: Brand.purple100,
      onPrimaryContainer: Brand.purple,
      secondary: Brand.purpleLight,
      onSecondary: Colors.white,
      tertiary: Brand.orange,
      onTertiary: Colors.white,
      surface: Colors.white,
      onSurface: Brand.gray900,
      surfaceContainerHighest: Brand.gray100,
      error: Brand.error,
      outline: Brand.gray300,
      outlineVariant: Brand.gray200,
    );

    OutlineInputBorder border(Color color, [double width = 2]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.radius),
          borderSide: BorderSide(color: color, width: width),
        );

    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.radius));

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Nunito',
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.white,
      textTheme: _textTheme,
      primaryTextTheme: _textTheme,
      dividerColor: Brand.gray200,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: nunito(14, 600, color: Brand.gray700),
        floatingLabelStyle: nunito(14, 600, color: Brand.purple),
        hintStyle: nunito(14, 400, color: Brand.gray500),
        errorStyle: nunito(13, 400, color: Brand.error),
        border: border(Brand.gray200),
        enabledBorder: border(Brand.gray200),
        focusedBorder: border(Brand.purpleLight),
        errorBorder: border(const Color(0xFFFCA5A5)),
        focusedErrorBorder: border(Brand.error),
        disabledBorder: border(Brand.gray200, 1),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Brand.purple,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Brand.gray400,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: buttonShape,
          textStyle: nunito(14, 600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Brand.purple,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Brand.gray400,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          shape: buttonShape,
          elevation: 0,
          textStyle: nunito(14, 600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Brand.purple,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          side: const BorderSide(color: Brand.purple, width: 2),
          shape: buttonShape,
          textStyle: nunito(14, 600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Brand.purpleLight,
          textStyle: nunito(14, 600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: Brand.gray600),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shadowColor: const Color(0x33000000),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.cardRadius),
          side: const BorderSide(color: Brand.gray200),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: Brand.purple,
        secondarySelectedColor: Brand.purple,
        side: const BorderSide(color: Brand.gray300),
        labelStyle: nunito(13, 500, color: Brand.gray700),
        secondaryLabelStyle: nunito(13, 500, color: Colors.white),
        checkmarkColor: Colors.white,
        shape: const StadiumBorder(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.cardRadius)),
        titleTextStyle: nunito(18, 600, color: Brand.gray900),
        contentTextStyle: nunito(14, 400, color: Brand.gray600),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Brand.gray900,
        contentTextStyle: nunito(14, 500, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.radius)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: Brand.purple,
        inactiveTrackColor: Brand.gray200,
        thumbColor: Brand.purple,
        overlayColor: Brand.purple.withValues(alpha: 0.12),
        trackHeight: 6,
        valueIndicatorColor: Brand.purple,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Brand.purple,
        linearTrackColor: Brand.gray200,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Brand.purpleLight : null,
        ),
        side: const BorderSide(color: Brand.gray300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Brand.purpleLight : Brand.gray400,
        ),
      ),
      dividerTheme: const DividerThemeData(color: Brand.gray200, space: 1),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Brand.purple,
        selectionHandleColor: Brand.purple,
      ),
      listTileTheme: const ListTileThemeData(iconColor: Brand.purple),
      expansionTileTheme: const ExpansionTileThemeData(
        iconColor: Brand.purple,
        collapsedIconColor: Brand.gray500,
        shape: Border(),
        collapsedShape: Border(),
      ),
    );
  }
}
