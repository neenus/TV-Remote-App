import 'package:material_ui/material_ui.dart';

import '../glass_panel.dart';
import '../theme.dart';

/// Glass ring with four arrows and a glowing OK button. Buttons are supplied
/// by the caller so the screen owns key handling.
class DPad extends StatelessWidget {
  const DPad({
    super.key,
    required this.up,
    required this.down,
    required this.left,
    required this.right,
    required this.ok,
    this.size = 260,
  });

  final Widget up, down, left, right, ok;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            GlassPanel(radius: size / 2, child: SizedBox.expand()),
            Align(alignment: Alignment.topCenter, child: up),
            Align(alignment: Alignment.bottomCenter, child: down),
            Align(alignment: Alignment.centerLeft, child: left),
            Align(alignment: Alignment.centerRight, child: right),
            ok,
          ],
        ),
      );
}

class OkDisc extends StatelessWidget {
  const OkDisc({super.key, this.size = 92});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AuroraColors.lilac, AuroraColors.magenta]),
          boxShadow: [
            BoxShadow(
                color: AuroraColors.magenta.withValues(alpha: 0.45),
                blurRadius: 24,
                spreadRadius: 1),
          ],
        ),
        child: const Text('OK',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      );
}
