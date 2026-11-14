import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/tv_device.dart';
import 'package:tv_remote/discovery/lg_discovery.dart';

const lgReply = 'HTTP/1.1 200 OK\r\n'
    'CACHE-CONTROL: max-age=1800\r\n'
    'LOCATION: http://192.168.1.50:1234/dd.xml\r\n'
    'ST: urn:lge-com:service:webos-second-screen:1\r\n'
    'USN: uuid:abcd-1234::urn:lge-com:service:webos-second-screen:1\r\n\r\n';

void main() {
  test('parse_lg_ssdp_response', () {
    final d = parseSsdpResponse(lgReply);
    expect(d, isNotNull);
    expect(d!.id, 'abcd-1234');
    expect(d.host, '192.168.1.50');
    expect(d.brand, TvBrand.lg);
    expect(d.name, 'LG TV');
  });

  test('parse_unsupported_brand_returns_null', () {
    const sonos = 'HTTP/1.1 200 OK\r\nLOCATION: http://192.168.1.9:1400/xml/device_description.xml\r\n'
        'ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\nUSN: uuid:RINCON_X::urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n';
    expect(parseSsdpResponse(sonos), isNull);
  });

  test('parse_roku_response_uses_the_serial_as_the_id', () {
    const roku = 'HTTP/1.1 200 OK\r\nLOCATION: http://192.168.1.9:8060/\r\n'
        'ST: roku:ecp\r\nUSN: uuid:roku:ecp:X00A123456\r\n\r\n';
    final d = parseSsdpResponse(roku);
    expect(d?.brand, TvBrand.roku);
    expect(d?.id, 'roku-X00A123456');
    expect(d?.host, '192.168.1.9');
    expect(d?.name, 'Roku TV');
  });

  test('two_rokus_get_different_ids', () {
    String reply(String serial) => 'HTTP/1.1 200 OK\r\nLOCATION: http://192.168.1.9:8060/\r\n'
        'ST: roku:ecp\r\nUSN: uuid:roku:ecp:$serial\r\n\r\n';
    expect(parseSsdpResponse(reply('A'))?.id, isNot(parseSsdpResponse(reply('B'))?.id));
  });

  test('a_roku_reply_without_a_serial_is_ignored', () {
    const reply = 'HTTP/1.1 200 OK\r\nLOCATION: http://192.168.1.9:8060/\r\n'
        'ST: roku:ecp\r\nUSN: uuid:roku:ecp:\r\n\r\n';
    expect(parseSsdpResponse(reply), isNull);
  });

  test('parse_garbage_returns_null', () {
    expect(parseSsdpResponse('???'), isNull);
    expect(parseSsdpResponse(''), isNull);
  });

  test('manual_device_has_manual_id_and_host', () {
    final d = manualDevice('10.0.0.7');
    expect(d.id, 'manual-10.0.0.7');
    expect(d.host, '10.0.0.7');
  });

  test('parse_samsung_ssdp_response', () {
    const reply = 'HTTP/1.1 200 OK\r\n'
        'LOCATION: http://192.168.1.60:7676/smp_7_\r\n'
        'ST: urn:samsung.com:device:RemoteControlReceiver:1\r\n'
        'USN: uuid:abcd-9999::urn:samsung.com:device:RemoteControlReceiver:1\r\n\r\n';
    final d = parseSsdpResponse(reply);
    expect(d, isNotNull);
    expect(d!.brand, TvBrand.samsung);
    expect(d.id, 'abcd-9999');
    expect(d.host, '192.168.1.60');
    expect(d.name, 'Samsung TV');
  });

  test('manual_device_brand_and_name', () {
    final s = manualDevice('10.0.0.7', brand: TvBrand.samsung);
    expect(s.brand, TvBrand.samsung);
    expect(s.name, 'Samsung TV (10.0.0.7)');
    expect(manualDevice('10.0.0.7').name, 'LG TV (10.0.0.7)');
  });

  test('parse_samsung_dial_reply_by_server_header', () {
    const reply = 'HTTP/1.1 200 OK\r\n'
        'LOCATION: http://192.168.1.61:7676/dd.xml\r\n'
        'ST: urn:dial-multiscreen-org:service:dial:1\r\n'
        'USN: uuid:dial-1234::urn:dial-multiscreen-org:service:dial:1\r\n'
        'SERVER: SHP, UPnP/1.0, Samsung UPnP SDK/1.0\r\n\r\n';
    final d = parseSsdpResponse(reply);
    expect(d?.brand, TvBrand.samsung);
    expect(d?.host, '192.168.1.61');
  });

  test('dial_reply_from_another_brand_is_ignored', () {
    const reply = 'HTTP/1.1 200 OK\r\n'
        'LOCATION: http://192.168.1.9:8060/dial/dd.xml\r\n'
        'ST: urn:dial-multiscreen-org:service:dial:1\r\n'
        'USN: uuid:roku-1::urn:dial-multiscreen-org:service:dial:1\r\n'
        'SERVER: Roku/12.0 UPnP/1.0 Roku/12.0\r\n\r\n';
    expect(parseSsdpResponse(reply), isNull);
  });

  test('older_samsung_manual_device_is_named_samsung', () {
    final d = manualDevice('10.0.0.7', brand: TvBrand.samsungLegacy);
    expect(d.brand, TvBrand.samsungLegacy);
    expect(d.name, 'Samsung TV (10.0.0.7)');
  });

  test('brand_labels_distinguish_the_older_samsung_option', () {
    expect(brandLabel(TvBrand.samsung), 'Samsung (2016 or newer)');
    expect(brandLabel(TvBrand.samsungEncrypted), 'Samsung (2014-2015)');
    expect(brandLabel(TvBrand.samsungLegacy), 'Samsung (2013 or older)');
    expect(brandLabel(TvBrand.fireTv), 'Fire TV');
    expect(brandLabel(TvBrand.roku), 'Roku');
    expect(brandLabel(TvBrand.androidTv), 'Android TV (Sony, Philips…)');
    expect(manualDevice('10.0.0.9', brand: TvBrand.androidTv).name, 'Android TV (10.0.0.9)');
    expect(manualDevice('10.0.0.8', brand: TvBrand.fireTv).name, 'Fire TV (10.0.0.8)');
  });
}
