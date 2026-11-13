import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/key_store.dart';
import 'core/tv_device.dart';
import 'core/tv_driver.dart';
import 'discovery/lg_discovery.dart';
import 'drivers/lg/lg_driver.dart';
import 'drivers/lg/transport.dart';
import 'storage/tv_repository.dart';

/// Must be overridden in main() with the loaded SharedPreferences instance.
final sharedPrefsProvider = Provider<SharedPreferences>(
    (ref) => throw UnimplementedError('sharedPrefsProvider not overridden'));

final tvRepositoryProvider =
    Provider((ref) => TvRepository(ref.watch(sharedPrefsProvider)));

final keyStoreProvider = Provider<KeyStore>((ref) => SecureKeyStore());

/// Accumulates TVs found on the network; emits an empty list first.
final discoveredTvsProvider = StreamProvider.autoDispose<List<TvDevice>>((ref) async* {
  final list = <TvDevice>[];
  yield list;
  await for (final d in discoverLg()) {
    list.add(d);
    yield List.of(list);
  }
});

/// Re-scan used to find a saved TV whose IP changed.
final rediscoverProvider = Provider<Stream<TvDevice> Function()>(
    (ref) => () => discoverLg(timeout: const Duration(seconds: 3)));

/// Creates a driver for a TV. The session screen owns (and disposes) it.
final driverFactoryProvider = Provider<TvDriver Function(TvDevice)>((ref) {
  final keys = ref.watch(keyStoreProvider);
  return (device) => LgDriver(device, keys, WebSocketTransport.new);
});
