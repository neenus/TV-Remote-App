import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// Fires [onFire] on pointer-down, then repeats while held.
class HoldRepeat extends StatefulWidget {
  const HoldRepeat({
    super.key,
    required this.onFire,
    required this.child,
    this.initialDelay = const Duration(milliseconds: 400),
    this.interval = const Duration(milliseconds: 120),
  });

  final VoidCallback onFire;
  final Widget child;
  final Duration initialDelay;
  final Duration interval;

  @override
  State<HoldRepeat> createState() => _HoldRepeatState();
}

class _HoldRepeatState extends State<HoldRepeat> {
  Timer? _delay;
  Timer? _repeat;

  void _start() {
    widget.onFire();
    _stop();
    _delay = Timer(widget.initialDelay, () {
      widget.onFire();
      _repeat = Timer.periodic(widget.interval, (_) => widget.onFire());
    });
  }

  void _stop() {
    _delay?.cancel();
    _repeat?.cancel();
    _delay = null;
    _repeat = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _start(),
        onPointerUp: (_) => _stop(),
        onPointerCancel: (_) => _stop(),
        child: widget.child,
      );
}
