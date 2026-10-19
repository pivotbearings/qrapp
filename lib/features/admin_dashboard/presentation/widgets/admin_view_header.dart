import 'package:flutter/material.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';

/// Clean, minimalistic, fully responsive header for admin views
/// Adapts gracefully from 320px mobile screens to ultra-wide displays
/// Subtitles removed globally across all admin pages as requested.
class AdminViewHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  const AdminViewHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 650;

        if (isCompact) {
          // Mobile / narrow screen layout: stack vertically
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.headlineSm.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (actions != null && actions!.isNotEmpty) ...[
                const SizedBox(height: AppDimensions.spaceMd),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: actions!,
                ),
              ],
              const SizedBox(height: AppDimensions.spaceMd),
            ],
          );
        }

        // Desktop / wide screen layout: side-by-side with Expanded title
        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(title, style: AppTypography.headlineLg),
                ),
                if (actions != null && actions!.isNotEmpty) ...[
                  const SizedBox(width: AppDimensions.spaceMd),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    alignment: WrapAlignment.end,
                    children: actions!,
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppDimensions.spaceLg),
          ],
        );
      },
    );
  }
}
