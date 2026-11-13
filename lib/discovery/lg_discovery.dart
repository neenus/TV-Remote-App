import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/tv_device.dart';

const _lgSt = 'urn:lge-com:service:webos-second-screen:1';

TvDevice? parseSsdpResponse(String raw) {
  final headers = <String, String>{};
  for (final line in const LineSplitter().convert(raw)) {
    final i = line.indexOf(':');
    if (i <= 0) continue;
    headers[line.substring(0, i).trim().toUpperCase()] =
        line.substring(i + 1).trim();
  }
  final st = headers['ST'] ?? '';
  final usn = headers['USN'] ?? '';
  if (!st.contains('lge-com') && !usn.contains('lge-com')) return null;
  final id = RegExp(r'uuid:([^:]+)').firstMatch(usn)?.group(1);
  final host = Uri.tryParse(headers['LOCATION'] ?? '')?.host;
  if (id == null || host == null || host.isEmpty) return null;
  return TvDevice(id: id, name: 'LG TV', brand: TvBrand.lg, host: host);
}

TvDevice manualDevice(String host) => TvDevice(
    id: 'manual-$host', name: 'LG TV ($host)', brand: TvBrand.lg, host: host);

Stream<TvDevice> discoverLg(
    {Duration timeout = const Duration(seconds: 4)}) async* {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final controller = StreamController<TvDevice>();
  final seen = <String>{};
  socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = socket.receive();
    if (dg == null) return;
    final d = parseSsdpResponse(utf8.decode(dg.data, allowMalformed: true));
    if (d != null && seen.add(d.id)) controller.add(d);
  });
  final request = 'M-SEARCH * HTTP/1.1\r\n'
      'HOST: 239.255.255.250:1900\r\n'
      'MAN: "ssdp:discover"\r\n'
      'MX: 2\r\n'
      'ST: $_lgSt\r\n\r\n';
  socket.send(utf8.encode(request), InternetAddress('239.255.255.250'), 1900);
  Timer(timeout, () {
    socket.close();
    controller.close();
  });
  yield* controller.stream;
}
