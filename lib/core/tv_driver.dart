import 'tv_key.dart';

class TvCapabilities {
  const TvCapabilities(this.keys);
  final Set<TvKey> keys;
  bool supports(TvKey k) => keys.contains(k);
}

sealed class TvConnectionState {
  const TvConnectionState();
}

class Disconnected extends TvConnectionState {
  const Disconnected();
}

class Connecting extends TvConnectionState {
  const Connecting();
}

class AwaitingPairing extends TvConnectionState {
  const AwaitingPairing();
}

class Connected extends TvConnectionState {
  const Connected();
}

class Failed extends TvConnectionState {
  const Failed(this.error);
  final Object error;
}

sealed class TvError implements Exception {
  const TvError(this.message);
  final String message;
  @override
  String toString() => '$runtimeType: $message';
}

class TvConnectionError extends TvError {
  const TvConnectionError([super.message = 'Could not reach the TV']);
}

class PairingDenied extends TvError {
  const PairingDenied([super.message = 'Pairing was denied on the TV']);
}

class InvalidClientKey extends TvError {
  const InvalidClientKey([super.message = 'Stored pairing key was rejected']);
}

abstract class TvDriver {
  TvCapabilities get capabilities;
  Stream<TvConnectionState> get state;
  Future<void> connect();
  Future<void> sendKey(TvKey key);
  Future<void> dispose();
}
