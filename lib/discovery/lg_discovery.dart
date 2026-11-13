import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/tv_device.dart';

const _lgSt = 'urn:lge-com:service:webos-second-screen:1';
const _samsungSt = 'urn:samsung.com:device:RemoteControlReceiver:1';
// Newer Samsung TVs may not answer the legacy search above but do answer DIAL.
const _dialSt = 'urn:dial-multiscreen-org:service:dial:1';

/// Label for choosing a brand (Add-by-IP).
String brandLabel(TvBrand b) => switch (b) {
      TvBrand.lg => 'LG',
      TvBrand.samsung => 'Samsung (2016 or newer)',
      TvBrand.samsungEncrypted => 'Samsung (2014-2015)',
      TvBrand.samsungLegacy => 'Samsung (2013 or older)',
    };

/// The brand as it appears in a TV's name.
String brandName(TvBrand b) => switch (b) {
      TvBrand.lg => 'LG',
      TvBrand.samsung || TvBrand.samsungEncrypted || TvBrand.samsungLegacy => 'Samsung',
    };

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
  final TvBrand brand;
  if (st.contains('lge-com') || usn.contains('lge-com')) {
    brand = TvBrand.lg;
  } else if (st.contains('samsung.com') ||
      usn.contains('samsung.com') ||
      (st.contains('dial-multiscreen') &&
          (headers['SERVER'] ?? '').toLowerCase().contains('samsung'))) {
    brand = TvBrand.samsung;
  } else {
    return null;
  }
  final id = RegExp(r'uuid:([^:]+)').firstMatch(usn)?.group(1);
  final host = Uri.tryParse(headers['LOCATION'] ?? '')?.host;
  if (id == null || host == null || host.isEmpty) return null;
  return TvDevice(id: id, name: '${brandName(brand)} TV', brand: brand, host: host);
}

TvDevice manualDevice(String host, {TvBrand brand = TvBrand.lg}) => TvDevice(
    id: 'manual-$host',
    name: '${brandName(brand)} TV ($host)',
    brand: brand,
    host: host);

/// Looks for LG and Samsung TVs with one multicast socket.
Stream<TvDevice> discoverTvs(
    {Duration timeout = const Duration(seconds: 4)}) async* {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final controller = StreamController<TvDevice>();
  final seen = <String>{};
  socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = socket.receive();
    if (dg == null) return;
    final d = parseSsdpResponse(utf8.decode(dg.data, allowMalformed: true));
    // One TV can answer several searches with different ids: dedupe by address.
    if (d != null && seen.add(d.host)) controller.add(d);
  });
  for (final st in const [_lgSt, _samsungSt, _dialSt]) {
    final request = 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 2\r\n'
        'ST: $st\r\n\r\n';
    socket.send(utf8.encode(request), InternetAddress('239.255.255.250'), 1900);
  }
  Timer(timeout, () {
    socket.close();
    controller.close();
  });
  yield* controller.stream;
}
