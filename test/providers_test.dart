import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_remote/core/tv_device.dart';
import 'package:tv_remote/drivers/lg/lg_driver.dart';
import 'package:tv_remote/drivers/android_tv/android_tv_driver.dart';
import 'package:tv_remote/drivers/fire_tv/fire_tv_driver.dart';
import 'package:tv_remote/drivers/roku/roku_driver.dart';
import 'package:tv_remote/drivers/samsung/samsung_driver.dart';
import 'package:tv_remote/drivers/samsung/samsung_encrypted_driver.dart';
import 'package:tv_remote/drivers/samsung/samsung_legacy_driver.dart';
import 'package:tv_remote/providers.dart';

void main() {
  test('driver_factory_picks_the_driver_for_the_brand', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
    ]);
    addTearDown(container.dispose);
    final make = container.read(driverFactoryProvider);
    const lg = TvDevice(id: 'a', name: 'A', brand: TvBrand.lg, host: 'h');
    const samsung = TvDevice(id: 'b', name: 'B', brand: TvBrand.samsung, host: 'h');
    expect(make(lg), isA<LgDriver>());
    expect(make(samsung), isA<SamsungDriver>());
    const legacy = TvDevice(id: 'c', name: 'C', brand: TvBrand.samsungLegacy, host: 'h');
    expect(make(legacy), isA<SamsungLegacyDriver>());
    const encrypted = TvDevice(id: 'd', name: 'D', brand: TvBrand.samsungEncrypted, host: 'h');
    expect(make(encrypted), isA<SamsungEncryptedDriver>());
    const fire = TvDevice(id: 'e', name: 'E', brand: TvBrand.fireTv, host: 'h');
    expect(make(fire), isA<FireTvDriver>());
    const roku = TvDevice(id: 'f', name: 'F', brand: TvBrand.roku, host: 'h');
    expect(make(roku), isA<RokuDriver>());
    const atv = TvDevice(id: 'g', name: 'G', brand: TvBrand.androidTv, host: 'h');
    expect(make(atv), isA<AndroidTvDriver>());
  });
}
