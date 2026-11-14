import 'package:material_ui/material_ui.dart';

import 'theme.dart';

class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.4, -0.8),
            radius: 1.4,
            colors: [
              AuroraColors.violet,
              AuroraColors.deepViolet,
              AuroraColors.deepNavy,
            ],
            stops: [0, 0.4, 1],
          ),
        ),
        child: child,
      );
}
