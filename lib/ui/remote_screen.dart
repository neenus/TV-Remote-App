import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/tv_driver.dart';
import '../core/tv_key.dart';
import 'aurora_background.dart';
import 'glass_panel.dart';
import 'theme.dart';
import 'widgets/dpad.dart';
import 'widgets/key_button.dart';

class RemoteScreen extends StatelessWidget {
  const RemoteScreen({
    super.key,
    required this.driver,
    required this.tvName,
    required this.onPower,
  });

  final TvDriver driver;
  final String tvName;
  final Future<void> Function() onPower;

  Future<void> _guard(BuildContext context, Future<void> Function() action) async {
    HapticFeedback.lightImpact();
    try {
      await action();
    } catch (e) {
      if (!context.mounted) return;
      final text = e is TvError ? e.message : 'Something went wrong';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Widget _btn(BuildContext context, TvKey k, Widget child,
      {bool repeat = false, bool glass = true, double? width, double radius = 16, double? height = 52}) {
    return KeyButton(
      key: ValueKey('key-${k.name}'),
      enabled: driver.capabilities.supports(k),
      repeat: repeat,
      glass: glass,
      radius: radius,
      width: width,
      height: height,
      onPress: () => _guard(context, () => driver.sendKey(k)),
      child: child,
    );
  }

  Widget _arrow(BuildContext context, TvKey k, IconData icon) =>
      _btn(context, k, Icon(icon, size: 34), repeat: true, glass: false, width: 72, height: 72);

  Widget _rocker(BuildContext context, String label, TvKey plus, TvKey minus) =>
      GlassPanel(
        radius: 28,
        child: SizedBox(
          width: 84,
          child: Column(children: [
            _btn(context, plus, const Icon(Icons.add), repeat: true, glass: false, height: 64),
            Text(label,
                style: const TextStyle(
                    color: AuroraColors.textSecondary, fontSize: 11, letterSpacing: 2)),
            _btn(context, minus, const Icon(Icons.remove), repeat: true, glass: false, height: 64),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: AuroraBackground(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Column(children: [
                  Row(children: [
                    Expanded(
                      child: Text(tvName.toUpperCase(),
                          style: const TextStyle(
                              color: AuroraColors.textSecondary,
                              letterSpacing: 3,
                              fontSize: 13)),
                    ),
                    KeyButton(
                      key: const ValueKey('key-power'),
                      enabled: true,
                      width: 48,
                      height: 48,
                      radius: 24,
                      onPress: () => _guard(context, onPower),
                      child: const Icon(Icons.power_settings_new),
                    ),
                  ]),
                  const SizedBox(height: 28),
                  DPad(
                    up: _arrow(context, TvKey.up, Icons.keyboard_arrow_up),
                    down: _arrow(context, TvKey.down, Icons.keyboard_arrow_down),
                    left: _arrow(context, TvKey.left, Icons.keyboard_arrow_left),
                    right: _arrow(context, TvKey.right, Icons.keyboard_arrow_right),
                    ok: _btn(context, TvKey.ok, const OkDisc(),
                        glass: false, width: 92, height: 92),
                  ),
                  const SizedBox(height: 28),
                  Row(children: [
                    Expanded(child: _btn(context, TvKey.home, const Icon(Icons.home_outlined))),
                    const SizedBox(width: 12),
                    Expanded(child: _btn(context, TvKey.back, const Icon(Icons.arrow_back))),
                    const SizedBox(width: 12),
                    Expanded(child: _btn(context, TvKey.menu, const Icon(Icons.menu))),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _btn(context, TvKey.rewind, const Icon(Icons.fast_rewind))),
                    const SizedBox(width: 12),
                    Expanded(child: _btn(context, TvKey.play, const Icon(Icons.play_arrow))),
                    const SizedBox(width: 12),
                    Expanded(child: _btn(context, TvKey.pause, const Icon(Icons.pause))),
                    const SizedBox(width: 12),
                    Expanded(child: _btn(context, TvKey.fastForward, const Icon(Icons.fast_forward))),
                  ]),
                  const SizedBox(height: 24),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _rocker(context, 'VOL', TvKey.volumeUp, TvKey.volumeDown),
                    _btn(context, TvKey.mute, const Icon(Icons.volume_off_outlined),
                        width: 64, height: 64, radius: 32),
                    _rocker(context, 'CH', TvKey.channelUp, TvKey.channelDown),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      );
}
