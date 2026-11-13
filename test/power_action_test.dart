import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/fake_driver.dart';
import 'package:tv_remote/core/tv_device.dart';
import 'package:tv_remote/core/tv_driver.dart';
import 'package:tv_remote/core/tv_key.dart';
import 'package:tv_remote/power_action.dart';

class UnreachableDriver extends FakeDriver {
  @override
  Future<void> sendKey(TvKey key) async => throw const TvConnectionError();
}

const noMac = TvDevice(id: 'a', name: 'A', brand: TvBrand.lg, host: 'h');
const withMac =
    TvDevice(id: 'a', name: 'A', brand: TvBrand.lg, host: 'h', mac: 'AA:BB:CC:DD:EE:FF');

void main() {
  test('power_when_reachable_sends_power_key', () async {
    final d = FakeDriver();
    await handlePower(device: noMac, driver: d, wake: (_, _) async {});
    expect(d.sent, [TvKey.power]);
  });

  test('power_when_unreachable_with_mac_sends_wake_on_lan', () async {
    String? woken;
    String? wokenHost;
    await handlePower(
        device: withMac,
        driver: UnreachableDriver(),
        wake: (m, h) async {
          woken = m;
          wokenHost = h;
        });
    expect(woken, 'AA:BB:CC:DD:EE:FF');
    expect(wokenHost, 'h', reason: 'the TV address is passed so its own network can be targeted');
  });

  test('power_when_unreachable_without_mac_shows_message', () async {
    await expectLater(
        handlePower(device: noMac, driver: UnreachableDriver(), wake: (_, _) async {}),
        throwsA(isA<TvConnectionError>()
            .having((e) => e.message, 'message', contains('No MAC saved'))));
  });
}
