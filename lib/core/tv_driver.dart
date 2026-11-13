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

/// The TV is showing a code on screen; call [TvDriver.submitPairingPin].
class AwaitingPin extends TvConnectionState {
  const AwaitingPin();
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
  /// With [pinPairing] the TV shows a code on screen instead of an accept
  /// prompt (for when you can't press OK on the TV's own remote).
  Future<void> connect({bool pinPairing = false});

  /// Sends the code the TV is showing. Ignored unless the TV asked for one.
  Future<void> submitPairingPin(String pin);
  Future<void> sendKey(TvKey key);

  /// The TV's own MAC address (used for Wake-on-LAN), or null if the TV can't
  /// say. Best effort: never throws and never opens a new connection.
  Future<String?> fetchMacAddress();
  Future<void> dispose();
}
