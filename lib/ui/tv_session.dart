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
  bool _searching = false;
  int _gen = 0; // bumped by every (re)start and on dispose to drop stale work

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _retry() {
    _refreshed = false;
    _start();
  }

  Future<void> _start() async {
    final gen = ++_gen;
    bool stale() => !mounted || gen != _gen;

    final oldSub = _sub, oldDriver = _driver;
    _sub = null;
    _driver = null;
    // Release the old attempt without waiting on it: cleanup must never block a retry.
    unawaited(oldSub?.cancel());
    unawaited(oldDriver?.dispose());

    final driver = ref.read(driverFactoryProvider)(_device);
    _driver = driver;
    setState(() {
      _status = const Connecting();
      _searching = false;
    });
    _sub = driver.state.listen((s) {
      if (stale()) return;
      setState(() {
        _status = s;
        if (s is Connected) _everConnected = true;
      });
    });
    try {
      await driver.connect();
      if (stale()) return;
      await ref.read(tvRepositoryProvider).save(_device);
    } on TvConnectionError catch (e) {
      if (stale()) return;
      // The TV may have a new DHCP address: look for it once before giving up.
      if (!_refreshed) {
        _refreshed = true;
        setState(() {
          _status = const Connecting();
          _searching = true;
        });
        var updated = _device;
        try {
          updated = await ref
              .read(tvRepositoryProvider)
              .refreshHost(_device, ref.read(rediscoverProvider)());
        } catch (_) {
          // Discovery unavailable (e.g. no network permission): fall through.
        }
        if (stale()) return;
        if (updated.host != _device.host) {
          _device = updated;
          return _start();
        }
      }
      _fail(e);
    } on TvError catch (e) {
      if (!stale()) _fail(e);
    } catch (_) {
      if (!stale()) _fail(const TvConnectionError());
    }
  }

  void _fail(TvError e) => setState(() {
        _status = Failed(e);
        _searching = false;
      });

  Future<void> _turnOn(String mac) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(wakeOnLanProvider)(mac);
      messenger.showSnackBar(const SnackBar(
          content: Text('Wake signal sent. Give the TV a few seconds, then tap Retry.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not send the wake signal')));
    }
  }

  @override
  void dispose() {
    _gen++;
    _sub?.cancel();
    _driver?.dispose();
    super.dispose();
  }

  Widget _message(Widget content) => Scaffold(
        body: AuroraBackground(
            child: SafeArea(
                child: Center(
                    child: Padding(padding: const EdgeInsets.all(28), child: content)))),
      );

  @override
  Widget build(BuildContext context) {
    final driver = _driver;
    if (_everConnected && driver != null) {
      return RemoteScreen(
        driver: driver,
        tvName: _device.name,
        onPower: () => handlePower(
            device: _device, driver: driver, wake: ref.read(wakeOnLanProvider)),
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
      final mac = _device.mac;
      return _message(Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off, size: 40, color: AuroraColors.magenta),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(onPressed: _retry, child: const Text('Retry')),
        if (mac != null && error is TvConnectionError)
          TextButton(onPressed: () => _turnOn(mac), child: const Text('Turn on TV')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
      ]));
    }
    return _message(Column(mainAxisSize: MainAxisSize.min, children: [
      const CircularProgressIndicator(),
      const SizedBox(height: 20),
      Text(_searching
          ? 'Searching for your TV…'
          : status is AwaitingPairing
              ? 'Accept the prompt on your TV'
              : 'Connecting to ${_device.name}…'),
    ]));
  }
}
