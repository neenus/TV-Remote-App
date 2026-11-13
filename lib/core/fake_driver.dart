import 'dart:async';

import 'tv_driver.dart';
import 'tv_key.dart';

class FakeDriver implements TvDriver {
  FakeDriver({TvCapabilities? capabilities})
      : capabilities = capabilities ?? TvCapabilities(TvKey.values.toSet());

  final List<TvKey> sent = [];
  String? mac;
  bool lastPinPairing = false;
  final List<String> submittedPins = [];
  final pinSubmitted = Completer<String>();
  int macFetches = 0;
  final _controller = StreamController<TvConnectionState>.broadcast();

  @override
  final TvCapabilities capabilities;

  @override
  Stream<TvConnectionState> get state => _controller.stream;

  void emit(TvConnectionState s) => _controller.add(s);

  @override
  Future<void> connect({bool pinPairing = false}) async {
    lastPinPairing = pinPairing;
    emit(const Connected());
  }

  @override
  Future<void> submitPairingPin(String pin) async {
    submittedPins.add(pin);
    if (!pinSubmitted.isCompleted) pinSubmitted.complete(pin);
  }

  @override
  Future<void> sendKey(TvKey key) async => sent.add(key);

  @override
  Future<String?> fetchMacAddress() async {
    macFetches++;
    return mac;
  }

  @override
  Future<void> dispose() async {
    unawaited(_controller.close()); // see LgDriver.dispose
  }
}
