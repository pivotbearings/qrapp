import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_typography.dart';
import '../router/app_routes.dart';

/// Industrial Header / AppBar strictly in #ECECEC and #001F59
class IndustrialAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final Widget? leading;

  const IndustrialAppBar({
    super.key,
    required this.title,
    this.showBackButton = true,
    this.onBack,
    this.actions,
    this.leading,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64.0);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64.0 + MediaQuery.paddingOf(context).top,
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        left: AppDimensions.gutterMobile,
        right: AppDimensions.gutterMobile,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(
            color: AppColors.primary,
            width: AppDimensions.borderWidthThin,
          ),
        ),
      ),
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (showBackButton)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.primary, size: 24),
              onPressed: onBack ?? () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  Navigator.pushReplacementNamed(context, AppRoutes.customerHome);
                }
              },
              tooltip: 'Back',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            )
          else
            // Industrial Bearing Application Icon
            Image.asset(
              'assets/company_logo.webp',
              height: 28,
              fit: BoxFit.contain,
            ),
          const SizedBox(width: AppDimensions.spaceSm),
          Expanded(
            child: Text(
              title,
              style: AppTypography.headlineSm,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (actions != null)
            ...actions!
          else ...[
            IconButton(
              icon: const Icon(Icons.support_agent, color: AppColors.primary, size: 22),
              onPressed: () {},
              tooltip: 'Support',
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
              ),
              child: const Center(
                child: Icon(Icons.person, size: 18, color: AppColors.background),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
