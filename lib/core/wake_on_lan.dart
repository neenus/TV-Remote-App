import 'dart:io';
import 'dart:typed_data';

Uint8List magicPacket(String mac) {
  final parts = mac.split(RegExp(r'[:-]'));
  if (parts.length != 6) throw FormatException('Invalid MAC address', mac);
  final bytes = <int>[];
  for (final p in parts) {
    final v = p.length == 2 ? int.tryParse(p, radix: 16) : null;
    if (v == null) throw FormatException('Invalid MAC address', mac);
    bytes.add(v);
  }
  return Uint8List.fromList([
    ...List.filled(6, 0xFF),
    for (var i = 0; i < 16; i++) ...bytes,
  ]);
}

/// Where to send the magic packet. The general broadcast only reaches the phone's
/// own network, so when the TV's address is known its own network's broadcast
/// address and the TV itself are tried too (a TV on another VLAN, like an IoT
/// network, never sees the general broadcast).
List<String> wakeTargets(String? host) {
  final targets = ['255.255.255.255'];
  final ip = host == null ? null : InternetAddress.tryParse(host);
  if (host != null && ip != null && ip.type == InternetAddressType.IPv4) {
    final parts = host.split('.');
    targets
      ..add('${parts[0]}.${parts[1]}.${parts[2]}.255')
      ..add(host);
  }
  return targets;
}

/// Sends the magic packet [repeats] times (a single UDP packet is easily lost) to
/// every target on the usual wake ports. A target that can't be reached doesn't
/// stop the others.
Future<void> sendWakeOnLan(
  String mac, {
  String? host,
  List<String>? targets,
  List<int> ports = const [9, 7],
  int repeats = 3,
  Duration gap = const Duration(milliseconds: 150),
}) async {
  final packet = magicPacket(mac);
  final destinations = targets ?? wakeTargets(host);
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  try {
    socket.broadcastEnabled = true;
    for (var i = 0; i < repeats; i++) {
      for (final target in destinations) {
        for (final port in ports) {
          try {
            socket.send(packet, InternetAddress(target), port);
          } catch (_) {}
        }
      }
      if (i < repeats - 1) await Future<void>.delayed(gap);
    }
  } finally {
    socket.close();
  }
}
