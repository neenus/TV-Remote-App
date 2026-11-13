import 'tv_key.dart';

class TvCapabilities {
  const TvCapabilities(this.keys,
      {this.typing = true,
      this.pairingChoice = false,
      this.announcesKeyboard = false,
      this.asciiOnlyTyping = false,
      this.pairingNote});
  final Set<TvKey> keys;

  /// Whether text typed on the phone can reach the TV (the keyboard panel).
  final bool typing;

  /// Whether pairing can be done either by accepting a prompt on the TV or by
  /// typing a code (only some TVs offer both).
  final bool pairingChoice;

  /// Whether the TV tells the app when a text field gets focus (so the typing
  /// panel can open by itself and a missing announcement is meaningful).
  final bool announcesKeyboard;

  /// The TV can only type plain ASCII; the phone's text box should refuse the rest.
  final bool asciiOnlyTyping;

  /// Extra guidance shown while the user has to confirm something on the TV.
  final String? pairingNote;
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

  /// True while the TV has a text field focused (e.g. a search box), false when
  /// it loses focus or the connection drops.
  Stream<bool> get keyboardFocus;

  /// Typing into the focused text field on the TV.
  Future<void> sendText(String text);
  Future<void> deleteText(int count);
  Future<void> sendEnter();

  /// The TV's own MAC address (used for Wake-on-LAN), or null if the TV can't
  /// say. Best effort: never throws and never opens a new remote-control connection
  /// (a driver may make a plain HTTP request).
  Future<String?> fetchMacAddress();
  Future<void> dispose();
}
