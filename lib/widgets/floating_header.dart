import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubit/theme_cubit.dart';
import '../cubit/reports_cubit.dart';
import '../theme/app_theme.dart';

class FloatingHeader extends StatelessWidget {
  final String title;
  final int reportCount;

  const FloatingHeader({
    super.key,
    this.title = 'Sahabat Assaffal',
    this.reportCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(50),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(50),
                border: Border.all(
                  color: isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
                color: isDarkMode
                    ? AppTheme.darkSurface.withOpacity(0.8)
                    : Colors.white.withOpacity(0.8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Logo section
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),

                  // Right section
                  Row(
                    children: [
                      // Report count
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Laporan',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                          BlocBuilder<ReportsCubit, ReportsState>(
                            builder: (context, state) {
                              final count = state is ReportsLoaded ? state.totalCount : 0;
                              return Text(
                                count.toString(),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: isDarkMode
                                      ? AppTheme.primaryBlueDark
                                      : AppTheme.primaryBlue,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),

                      // Theme toggle
                      BlocBuilder<ThemeCubit, ThemeState>(
                        builder: (context, state) {
                          return GestureDetector(
                            onTap: () => context.read<ThemeCubit>().toggleTheme(),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                    ? Colors.grey.shade800
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(50),
                              ),
                              child: Icon(
                                state.isDark ? Icons.wb_sunny : Icons.dark_mode,
                                size: 18,
                                color: state.isDark
                                    ? Colors.amber
                                    : Colors.grey.shade700,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
