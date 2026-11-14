import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import 'theme.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 16,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: AuroraColors.glassFill,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: AuroraColors.glassBorder),
            ),
            child: child,
          ),
        ),
      );
}
