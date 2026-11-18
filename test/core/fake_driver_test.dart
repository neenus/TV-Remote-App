import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/fake_driver.dart';
import 'package:tv_remote/core/tv_device.dart';
import 'package:tv_remote/core/tv_key.dart';

void main() {
  test('fake_driver_records_keys', () async {
    final d = FakeDriver();
    await d.sendKey(TvKey.volumeUp);
    expect(d.sent, [TvKey.volumeUp]);
  });

  test('tv_device_json_round_trip', () {
    const device = TvDevice(
        id: 'u1', name: 'LG TV', brand: TvBrand.lg, host: '192.168.1.5', mac: 'AA:BB:CC:DD:EE:FF');
    final back = TvDevice.fromJson(device.toJson());
    expect(back.id, device.id);
    expect(back.name, device.name);
    expect(back.brand, device.brand);
    expect(back.host, device.host);
    expect(back.mac, device.mac);
  });
}
