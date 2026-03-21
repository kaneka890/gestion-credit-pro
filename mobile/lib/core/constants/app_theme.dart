import 'package:flutter/material.dart';

/// Palette inspirée du drapeau ivoirien + finance
class AppColors {
  // Primaires
  static const orange = Color(0xFFF77F00);      // Orange CI
  static const vert = Color(0xFF009A44);         // Vert CI
  static const blanc = Color(0xFFFFFFFF);

  // Neutres
  static const fondSombre = Color(0xFF0F1923);
  static const fondCarte = Color(0xFF1A2535);
  static const fondInput = Color(0xFF243044);
  static const textePrincipal = Color(0xFFE8EDF4);
  static const texteSecondaire = Color(0xFF8A97AA);
  static const bordure = Color(0xFF2E3E55);

  // Statuts
  static const succes = Color(0xFF00C48C);
  static const avertissement = Color(0xFFFFB800);
  static const danger = Color(0xFFFF4757);
  static const info = Color(0xFF4D8AF0);

  // Score
  static Color couleurScore(int score) {
    if (score >= 75) return succes;
    if (score >= 55) return info;
    if (score >= 40) return avertissement;
    return danger;
  }
}

class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: null,
    colorScheme: ColorScheme.dark(
      primary: AppColors.orange,
      secondary: AppColors.vert,
      surface: AppColors.fondCarte,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.fondSombre,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.fondSombre,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: null,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textePrincipal,
      ),
      iconTheme: IconThemeData(color: AppColors.textePrincipal),
    ),
    cardTheme: CardThemeData(
      color: AppColors.fondCarte,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.bordure, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.fondInput,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.bordure),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.bordure),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.orange, width: 2),
      ),
      labelStyle: const TextStyle(color: AppColors.texteSecondaire),
      hintStyle: const TextStyle(color: AppColors.texteSecondaire),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: null,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: AppColors.textePrincipal, fontWeight: FontWeight.w700),
      headlineMedium: TextStyle(color: AppColors.textePrincipal, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(color: AppColors.textePrincipal, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: AppColors.textePrincipal, fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(color: AppColors.textePrincipal),
      bodyMedium: TextStyle(color: AppColors.texteSecondaire),
      labelLarge: TextStyle(color: AppColors.textePrincipal, fontWeight: FontWeight.w500),
    ),
  );
}
