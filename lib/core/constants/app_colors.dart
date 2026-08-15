import 'package:flutter/material.dart';

class AppColors {
  // Dark Theme Palette (Primary UI)
  static const Color darkBackground = Color(0xFF0A0A0C);
  static const Color darkSurface = Color(0xFF141418);
  static const Color darkBorder = Color(0xFF24242B);
  
  // Brand Greens
  static const Color primaryGreen = Color(0xFF0C831F);
  static const Color lightGreen = Color(0xFF6DBE45);
  static const Color tealGreen = Color(0xFF0F766E);
  
  // Gradients
  static const Gradient brandGradient = LinearGradient(
    colors: [lightGreen, primaryGreen],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const Gradient accentGradient = LinearGradient(
    colors: [tealGreen, Color(0xFF115E59)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Status Colors
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);
  
  // Typography
  static const Color textPrimary = Color(0xFFE2E8F0); // slate-200
  static const Color textSecondary = Color(0xFF94A3B8); // slate-400
  static const Color textMuted = Color(0xFF64748B); // slate-500
  static const Color textOnPrimary = Colors.white;
}
