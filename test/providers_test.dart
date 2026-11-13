import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_remote/core/tv_device.dart';
import 'package:tv_remote/drivers/lg/lg_driver.dart';
import 'package:tv_remote/drivers/samsung/samsung_driver.dart';
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
  });
}
