import 'package:material_ui/material_ui.dart';

class AuroraColors {
  static const deepNavy = Color(0xFF090A1A);
  static const violet = Color(0xFF6B4CFF);
  static const deepViolet = Color(0xFF1A1040);
  static const magenta = Color(0xFFFF7AD9);
  static const lilac = Color(0xFF8F7CFF);
  static const glassFill = Color(0x14FFFFFF); // white 8%
  static const glassBorder = Color(0x2BFFFFFF); // white 17%
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFD8CCFF);
}

ThemeData auroraTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AuroraColors.deepNavy,
      colorScheme: const ColorScheme.dark(
        primary: AuroraColors.lilac,
        secondary: AuroraColors.magenta,
        surface: AuroraColors.deepViolet,
      ),
      textTheme: const TextTheme().apply(
        bodyColor: AuroraColors.textPrimary,
        displayColor: AuroraColors.textPrimary,
      ),
    );
