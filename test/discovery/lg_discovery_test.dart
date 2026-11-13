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

  test('parse_non_lg_response_returns_null', () {
    const roku = 'HTTP/1.1 200 OK\r\nLOCATION: http://192.168.1.9:8060/\r\n'
        'ST: roku:ecp\r\nUSN: uuid:roku:ecp:X\r\n\r\n';
    expect(parseSsdpResponse(roku), isNull);
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
}
