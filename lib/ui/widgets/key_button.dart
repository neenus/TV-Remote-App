import 'package:material_ui/material_ui.dart';

import '../glass_panel.dart';
import 'hold_repeat.dart';

class KeyButton extends StatelessWidget {
  const KeyButton({
    super.key,
    required this.child,
    required this.enabled,
    required this.onPress,
    this.repeat = false,
    this.glass = true,
    this.radius = 16,
    this.width,
    this.height = 52,
  });

  final Widget child;
  final bool enabled;
  final VoidCallback onPress;
  final bool repeat;
  final bool glass;
  final double radius;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    Widget body = SizedBox(
      width: width,
      height: height,
      child: Center(child: child),
    );
    if (glass) body = GlassPanel(radius: radius, child: body);
    if (enabled) {
      body = repeat
          ? HoldRepeat(onFire: onPress, child: body)
          : GestureDetector(
              behavior: HitTestBehavior.opaque, onTap: onPress, child: body);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(opacity: enabled ? 1 : 0.35, child: body),
    );
  }
}
