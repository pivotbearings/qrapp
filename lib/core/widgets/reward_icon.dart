import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Pixel-perfect vector SVG icon of the Reward Points / Loyalty Badge
/// Guaranteed crisp vector rendering across all platforms and release builds
/// without relying on Flutter icon font glyphs or tree-shaking.
class RewardIcon extends StatelessWidget {
  final double size;
  final Color color;

  const RewardIcon({
    super.key,
    this.size = 20,
    this.color = Colors.white,
  });

  // Material Card Giftcard / Reward Loyalty Vector
  static const String _rawSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor">
  <path d="M20 6h-2.18c.11-.31.18-.65.18-1 0-1.66-1.34-3-3-3-1.05 0-1.96.54-2.5 1.35l-.5.65-.5-.65C10.96 2.54 10.05 2 9 2 7.34 2 6 3.34 6 5c0 .35.07.69.18 1H4c-1.11 0-1.99.89-1.99 2L2 19c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2zm-5-2c.55 0 1 .45 1 1s-.45 1-1 1h-2.22l.8-1.07c.33-.44.83-.93 1.42-.93zM9 4c.59 0 1.09.49 1.42.93L11.22 6H9c-.55 0-1-.45-1-1s.45-1 1-1zm11 15H4v-2h16v2zm0-5H4V8h5.08L7 10.83 8.62 12 11 8.76V14h2V8.76l2.38 3.24 1.62-1.17L14.92 8H20v6z"/>
</svg>
''';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _rawSvg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

