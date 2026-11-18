import 'dart:async';
import 'dart:typed_data';

import 'package:tv_remote/drivers/android_tv/atv_crypto.dart';
import 'package:tv_remote/drivers/android_tv/atv_protobuf.dart';
import 'package:tv_remote/drivers/android_tv/atv_transport.dart';

import 'atv_goldens.dart';

Uint8List unhex(String s) => Uint8List.fromList(
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);

bool sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A scripted Android TV: pairing on 6467, remote control on 6466.
class FakeAtvTv {
  bool pairOpenFails = false;
  bool controlOpenFails = false;
  Duration openDelay = Duration.zero;
  bool silentPairing = false; // never answers the pairing request
  bool garbagePairing = false; // answers with a corrupt frame
  bool ignoreSecret = false; // never acknowledges the secret
  bool rejectSecret = false; // answers the secret with STATUS_BAD_SECRET
  bool closeControlBeforeStart = false; // drops the connection during the handshake
  bool errorInControl = false; // sends remote_error instead of starting
  bool noStart = false; // never sends remote_start
  final List<FakeAtvChannel> channels = [];

  /// The code the TV "shows": a checksum byte followed by this tail.
  String codeFor(AtvIdentity identity, {String tail = '2B3C'}) {
    final client = rsaPublicKeyFromCertDer(pemToDer(identity.certPem)!)!;
    final server = BigInt.parse(atvPair_server_n, radix: 16);
    for (var head = 0; head < 256; head++) {
      final code = '${head.toRadixString(16).padLeft(2, '0')}$tail'.toUpperCase();
      final secret = atvPairingSecret(
          clientN: client.n,
          clientE: client.e,
          serverN: server,
          serverE: BigInt.from(atvPair_server_e),
          code: code);
      if (secret != null) return code;
    }
    throw StateError('no code found');
  }

  AtvChannel make() {
    final c = FakeAtvChannel(this);
    channels.add(c);
    return c;
  }

  Iterable<FakeAtvChannel> get controlChannels => channels.where((c) => c.port == 6466);
  Iterable<FakeAtvChannel> get pairingChannels => channels.where((c) => c.port == 6467);

  /// Everything sent to the control port that was a key press, as raw messages.
  List<Uint8List> get keyMessages => [
        for (final c in controlChannels)
          for (final m in c.received)
            if (m.isNotEmpty && m[0] == 0x52) m // field 10, length-delimited
      ];
}

class FakeAtvChannel implements AtvChannel {
  FakeAtvChannel(this.tv);
  final FakeAtvTv tv;
  final _controller = StreamController<List<int>>.broadcast();
  final _parser = AtvFrameParser();
  final received = <Uint8List>[];
  bool _open = false;
  int? port;
  AtvIdentity? identity;

  @override
  bool get isOpen => _open;

  @override
  Stream<List<int>> get bytes => _controller.stream;

  @override
  Uint8List? get peerCertificateDer => unhex(atvPair_server_cert_der);

  @override
  Future<void> openSecure(String host, int port, AtvIdentity identity) async {
    if (tv.openDelay > Duration.zero) await Future<void>.delayed(tv.openDelay);
    if ((port == 6467 && tv.pairOpenFails) || (port == 6466 && tv.controlOpenFails)) {
      throw Exception('connection refused');
    }
    this.port = port;
    this.identity = identity;
    _open = true;
    if (port == 6466) {
      Timer(const Duration(milliseconds: 5), () {
        if (tv.errorInControl) {
          push(unhex(atvRecv_remote_error));
        } else {
          push(unhex(atvRecv_remote_configure));
        }
      });
    }
  }

  void push(List<int> message) => Timer(const Duration(milliseconds: 5), () {
        if (!_controller.isClosed) _controller.add(frameMessage(message));
      });

  void pushRaw(List<int> data) => Timer(const Duration(milliseconds: 5), () {
        if (!_controller.isClosed) _controller.add(data);
      });

  void closeFromRemote() {
    _open = false;
    _controller.close();
  }

  @override
  void send(List<int> data) {
    for (final m in _parser.add(data)) {
      received.add(m);
      port == 6467 ? _pairing(m) : _control(m);
    }
  }

  void _pairing(Uint8List m) {
    if (tv.silentPairing) return;
    if (tv.garbagePairing) {
      pushRaw([0xff, 0xff, 0xff, 0xff, 0xff, 0xff]);
      return;
    }
    if (sameBytes(m, poloPairingRequest('TV Remote'))) {
      push(unhex(atvRecv_pairing_request_ack));
    } else if (sameBytes(m, poloOptions())) {
      push(unhex(atvRecv_options));
    } else if (sameBytes(m, poloConfiguration())) {
      push(unhex(atvRecv_configuration_ack));
    } else if (m.length > 6 && m[5] == 0xC2 && m[6] == 0x02) {
      // a secret message (field 40, after the 5-byte header)
      if (tv.ignoreSecret) return;
      if (tv.rejectSecret) {
        push(unhex(atvRecv_bad_secret));
        return;
      }
      push(unhex(atvRecv_secret_ack));
    }
  }

  void _control(Uint8List m) {
    if (tv.closeControlBeforeStart && sameBytes(m, remoteConfigure(611))) {
      closeFromRemote();
      return;
    }
    if (sameBytes(m, remoteConfigure(611))) {
      push(unhex(atvRecv_remote_set_active));
    } else if (sameBytes(m, remoteSetActive(611))) {
      if (!tv.noStart) push(unhex(atvRecv_remote_start));
    }
  }

  @override
  Future<void> close() async {
    _open = false;
    if (!_controller.isClosed) await _controller.close();
  }
}
