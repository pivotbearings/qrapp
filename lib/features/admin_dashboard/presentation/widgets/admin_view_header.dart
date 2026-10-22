import 'package:flutter/material.dart';
import '../../../../core/constants/app_dimensions.dart';

/// Clean, minimalistic header wrapper for admin views.
///
/// Page titles are already prominently rendered in the global admin top header bar,
/// so in-page titles are suppressed to eliminate visual duplication.
/// When actions are provided (e.g. Refresh, Add, Search filters), they are
/// cleanly rendered at the top of the workstation view.
class AdminViewHeader extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final List<Widget>? actions;

  const AdminViewHeader({
    super.key,
    this.title,
    this.subtitle,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    if (actions == null || actions!.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 650;

        return Padding(
          padding: const EdgeInsets.only(bottom: AppDimensions.spaceMd),
          child: Align(
            alignment: isCompact ? Alignment.centerLeft : Alignment.centerRight,
            child: Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              alignment: isCompact ? WrapAlignment.start : WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions!,
            ),
          ),
        );
      },
    );
  }
}
