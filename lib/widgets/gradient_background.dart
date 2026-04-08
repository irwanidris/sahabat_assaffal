import 'package:flutter/material.dart';

class GradientBackground extends StatelessWidget {
  final Widget child;

  const GradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDarkMode
              ? [
                  const Color(0xFF111827),
                  const Color(0xFF1F2937),
                  const Color(0xFF374151),
                ]
              : [
                  const Color(0xFFF3F4F6),
                  const Color(0xFFE5E7EB),
                  const Color(0xFFD1D5DB),
                ],
        ),
      ),
      child: child,
    );
  }
}
