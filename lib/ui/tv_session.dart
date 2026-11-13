import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/tv_device.dart';
import '../core/tv_driver.dart';
import '../power_action.dart';
import '../providers.dart';
import 'aurora_background.dart';
import 'remote_screen.dart';
import 'theme.dart';

/// Connects to one TV, walks through pairing, then shows the remote.
class TvSession extends ConsumerStatefulWidget {
  const TvSession({super.key, required this.device});
  final TvDevice device;
  @override
  ConsumerState<TvSession> createState() => _TvSessionState();
}

class _TvSessionState extends ConsumerState<TvSession> {
  late TvDevice _device = widget.device;
  TvDriver? _driver;
  StreamSubscription<TvConnectionState>? _sub;
  TvConnectionState _status = const Connecting();
  bool _everConnected = false;
  bool _refreshed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _sub?.cancel();
    await _driver?.dispose();
    final driver = ref.read(driverFactoryProvider)(_device);
    _driver = driver;
    if (mounted) setState(() => _status = const Connecting());
    _sub = driver.state.listen((s) {
      if (!mounted) return;
      setState(() {
        _status = s;
        if (s is Connected) _everConnected = true;
      });
    });
    try {
      await driver.connect();
      await ref.read(tvRepositoryProvider).save(_device);
    } on TvConnectionError catch (e) {
      // The TV may have a new DHCP address: look for it once before giving up.
      if (!_refreshed) {
        _refreshed = true;
        final updated = await ref
            .read(tvRepositoryProvider)
            .refreshHost(_device, ref.read(rediscoverProvider)());
        if (updated.host != _device.host && mounted) {
          _device = updated;
          return _start();
        }
      }
      _fail(e);
    } on TvError catch (e) {
      _fail(e);
    }
  }

  void _fail(TvError e) {
    if (mounted) setState(() => _status = Failed(e));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _driver?.dispose();
    super.dispose();
  }

  Widget _message(Widget content) => Scaffold(
        body: AuroraBackground(
            child: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(28), child: content)))),
      );

  @override
  Widget build(BuildContext context) {
    final driver = _driver;
    if (_everConnected && driver != null) {
      return RemoteScreen(
        driver: driver,
        tvName: _device.name,
        onPower: () => handlePower(device: _device, driver: driver),
      );
    }
    final status = _status;
    if (status is Failed) {
      final error = status.error;
      final text = error is PairingDenied
          ? 'Pairing was denied. Accept the prompt on your TV to continue.'
          : error is TvError
              ? error.message
              : 'Something went wrong';
      return _message(Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off, size: 40, color: AuroraColors.magenta),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(onPressed: _start, child: const Text('Retry')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
      ]));
    }
    return _message(Column(mainAxisSize: MainAxisSize.min, children: [
      const CircularProgressIndicator(),
      const SizedBox(height: 20),
      Text(status is AwaitingPairing
          ? 'Accept the prompt on your TV'
          : 'Connecting to ${_device.name}…'),
    ]));
  }
}
