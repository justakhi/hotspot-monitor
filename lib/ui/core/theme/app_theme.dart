import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class AppTheme {
  static const Color downloadColor = Color(0xFF0EA5E9);
  static const Color uploadColor = Color(0xFFF59E0B);
  static const Color rootAccent = Color(0xFF10B981);
  static const Color nonRootAccent = Color(0xFF6366F1);

  static Color categoryColor(String category) {
    switch (category) {
      case 'Video':
        return const Color(0xFFEF4444);
      case 'Social':
        return const Color(0xFFEC4899);
      case 'Messaging':
        return const Color(0xFF22C55E);
      case 'Calls':
        return const Color(0xFF14B8A6);
      case 'Music':
        return const Color(0xFF8B5CF6);
      case 'Gaming':
        return const Color(0xFFF97316);
      case 'AI & Dev':
        return const Color(0xFF06B6D4);
      case 'Cloud & OS':
        return const Color(0xFF3B82F6);
      case 'Shopping':
        return const Color(0xFFEAB308);
      case 'Ads & Analytics':
        return const Color(0xFFA855F7);
      default:
        return const Color(0xFF64748B);
    }
  }

  static FThemeData light() => FTheme.neutral.light.touch;
  static FThemeData dark() => FTheme.neutral.dark.touch;
}
