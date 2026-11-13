import 'dart:async';

import 'tv_driver.dart';
import 'tv_key.dart';

class FakeDriver implements TvDriver {
  FakeDriver({TvCapabilities? capabilities})
      : capabilities = capabilities ?? TvCapabilities(TvKey.values.toSet());

  final List<TvKey> sent = [];
  final _controller = StreamController<TvConnectionState>.broadcast();

  @override
  final TvCapabilities capabilities;

  @override
  Stream<TvConnectionState> get state => _controller.stream;

  void emit(TvConnectionState s) => _controller.add(s);

  @override
  Future<void> connect() async => emit(const Connected());

  @override
  Future<void> sendKey(TvKey key) async => sent.add(key);

  @override
  Future<void> dispose() async {
    unawaited(_controller.close()); // see LgDriver.dispose
  }
}
