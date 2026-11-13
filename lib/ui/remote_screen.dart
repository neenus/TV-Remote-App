import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/tv_driver.dart';
import '../core/tv_key.dart';
import 'aurora_background.dart';
import 'glass_panel.dart';
import 'keyboard_sheet.dart';
import 'theme.dart';
import 'widgets/dpad.dart';
import 'widgets/key_button.dart';

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({
    super.key,
    required this.driver,
    required this.tvName,
    required this.onPower,
  });

  final TvDriver driver;
  final String tvName;
  final Future<void> Function() onPower;

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  StreamSubscription<bool>? _keyboardSub;
  bool _sheetOpen = false;
  bool _tvHasTextField = false;

  TvDriver get driver => widget.driver;

  @override
  void initState() {
    super.initState();
    // The TV tells us when a text field (e.g. search) gets focus.
    _keyboardSub = driver.keyboardFocus.listen((focused) {
      _tvHasTextField = focused;
      if (focused) {
        _openKeyboard();
      } else {
        _closeKeyboard();
      }
    });
  }

  @override
  void dispose() {
    _keyboardSub?.cancel();
    super.dispose();
  }

  void _openKeyboard() {
    if (_sheetOpen || !mounted) return;
    _sheetOpen = true;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => KeyboardSheet(
        showHint: !_tvHasTextField,
        onInsert: (t) => _run(() => driver.sendText(t)),
        onDelete: (n) => _run(() => driver.deleteText(n)),
        onEnter: () => _run(driver.sendEnter),
      ),
    ).whenComplete(() => _sheetOpen = false);
  }

  void _closeKeyboard() {
    if (_sheetOpen && mounted) Navigator.of(context).pop();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      final text = e is TvError ? e.message : 'Something went wrong';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _guard(Future<void> Function() action) {
    HapticFeedback.lightImpact();
    return _run(action);
  }

  Widget _btn(TvKey k, Widget child,
      {bool repeat = false,
      bool glass = true,
      double? width,
      double radius = 16,
      double? height = 52}) {
    return KeyButton(
      key: ValueKey('key-${k.name}'),
      enabled: driver.capabilities.supports(k),
      repeat: repeat,
      glass: glass,
      radius: radius,
      width: width,
      height: height,
      onPress: () => _guard(() => driver.sendKey(k)),
      child: child,
    );
  }

  Widget _arrow(TvKey k, IconData icon) => _btn(k, Icon(icon, size: 34),
      repeat: true, glass: false, width: 72, height: 72);

  Widget _rocker(String label, TvKey plus, TvKey minus) => GlassPanel(
        radius: 28,
        child: SizedBox(
          width: 84,
          child: Column(children: [
            _btn(plus, const Icon(Icons.add), repeat: true, glass: false, height: 64),
            Text(label,
                style: const TextStyle(
                    color: AuroraColors.textSecondary, fontSize: 11, letterSpacing: 2)),
            _btn(minus, const Icon(Icons.remove), repeat: true, glass: false, height: 64),
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
                      child: Text(widget.tvName.toUpperCase(),
                          style: const TextStyle(
                              color: AuroraColors.textSecondary,
                              letterSpacing: 3,
                              fontSize: 13)),
                    ),
                    KeyButton(
                      key: const ValueKey('open-keyboard'),
                      enabled: driver.capabilities.typing,
                      width: 48,
                      height: 48,
                      radius: 24,
                      onPress: _openKeyboard,
                      child: const Icon(Icons.keyboard_outlined),
                    ),
                    const SizedBox(width: 8),
                    KeyButton(
                      key: const ValueKey('key-power'),
                      enabled: true,
                      width: 48,
                      height: 48,
                      radius: 24,
                      onPress: () => _guard(widget.onPower),
                      child: const Icon(Icons.power_settings_new),
                    ),
                  ]),
                  const SizedBox(height: 28),
                  DPad(
                    up: _arrow(TvKey.up, Icons.keyboard_arrow_up),
                    down: _arrow(TvKey.down, Icons.keyboard_arrow_down),
                    left: _arrow(TvKey.left, Icons.keyboard_arrow_left),
                    right: _arrow(TvKey.right, Icons.keyboard_arrow_right),
                    ok: _btn(TvKey.ok, const OkDisc(), glass: false, width: 92, height: 92),
                  ),
                  const SizedBox(height: 28),
                  Row(children: [
                    Expanded(child: _btn(TvKey.home, const Icon(Icons.home_outlined))),
                    const SizedBox(width: 12),
                    Expanded(child: _btn(TvKey.back, const Icon(Icons.arrow_back))),
                    const SizedBox(width: 12),
                    Expanded(child: _btn(TvKey.menu, const Icon(Icons.menu))),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _btn(TvKey.rewind, const Icon(Icons.fast_rewind))),
                    const SizedBox(width: 12),
                    Expanded(child: _btn(TvKey.play, const Icon(Icons.play_arrow))),
                    const SizedBox(width: 12),
                    Expanded(child: _btn(TvKey.pause, const Icon(Icons.pause))),
                    const SizedBox(width: 12),
                    Expanded(child: _btn(TvKey.fastForward, const Icon(Icons.fast_forward))),
                  ]),
                  const SizedBox(height: 24),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _rocker('VOL', TvKey.volumeUp, TvKey.volumeDown),
                    _btn(TvKey.mute, const Icon(Icons.volume_off_outlined),
                        width: 64, height: 64, radius: 32),
                    _rocker('CH', TvKey.channelUp, TvKey.channelDown),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      );
}
