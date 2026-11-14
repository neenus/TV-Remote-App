import 'dart:async';

import 'tv_driver.dart';
import 'tv_key.dart';

class FakeDriver implements TvDriver {
  FakeDriver({TvCapabilities? capabilities})
      : capabilities =
            capabilities ??
                TvCapabilities(TvKey.values.toSet(), pairingChoice: true, announcesKeyboard: true);

  final List<TvKey> sent = [];
  final _keyboard = StreamController<bool>.broadcast();
  final List<String> typed = [];
  final List<int> deletes = [];
  int enters = 0;
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
  Stream<bool> get keyboardFocus => _keyboard.stream;

  void setKeyboardFocus(bool focused) => _keyboard.add(focused);

  @override
  Future<void> sendText(String text) async => typed.add(text);

  @override
  Future<void> deleteText(int count) async => deletes.add(count);

  @override
  Future<void> sendEnter() async => enters++;

  @override
  Future<String?> fetchMacAddress() async {
    macFetches++;
    return mac;
  }

  @override
  Future<void> dispose() async {
    unawaited(_controller.close()); // see LgDriver.dispose
    unawaited(_keyboard.close());
  }
}
