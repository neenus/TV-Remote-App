import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/key_store.dart';
import 'core/tv_device.dart';
import 'core/tv_driver.dart';
import 'core/wake_on_lan.dart';
import 'discovery/discovery_state.dart';
import 'discovery/lg_discovery.dart';
import 'drivers/lg/lg_driver.dart';
import 'drivers/lg/transport.dart';
import 'drivers/fire_tv/fire_tv_driver.dart';
import 'drivers/roku/roku_driver.dart';
import 'drivers/samsung/samsung_driver.dart';
import 'drivers/samsung/samsung_encrypted_driver.dart';
import 'drivers/samsung/samsung_encrypted_http.dart';
import 'drivers/samsung/samsung_legacy_driver.dart';
import 'drivers/samsung/tcp_transport.dart';
import 'storage/tv_repository.dart';

/// Must be overridden in main() with the loaded SharedPreferences instance.
final sharedPrefsProvider = Provider<SharedPreferences>(
    (ref) => throw UnimplementedError('sharedPrefsProvider not overridden'));

final tvRepositoryProvider =
    Provider((ref) => TvRepository(ref.watch(sharedPrefsProvider)));

final keyStoreProvider = Provider<KeyStore>((ref) => SecureKeyStore());

/// Accumulates TVs found on the network and reports when the scan finishes.
final discoveredTvsProvider = StreamProvider.autoDispose<DiscoveryState>((ref) async* {
  final list = <TvDevice>[];
  yield const DiscoveryState([], scanning: true);
  try {
    await for (final d in discoverTvs()) {
      list.add(d);
      yield DiscoveryState(List.of(list), scanning: true);
    }
  } catch (_) {
    // Scan unavailable (e.g. no network permission): finish with what we have.
  }
  yield DiscoveryState(List.of(list));
});

/// Re-scan used to find a saved TV whose IP changed.
final rediscoverProvider = Provider<Stream<TvDevice> Function()>(
    (ref) => () => discoverTvs(timeout: const Duration(seconds: 3)));

/// Creates a driver for a TV. The session screen owns (and disposes) it.
final driverFactoryProvider = Provider<TvDriver Function(TvDevice)>((ref) {
  final keys = ref.watch(keyStoreProvider);
  return (device) => switch (device.brand) {
        TvBrand.lg => LgDriver(device, keys, WebSocketTransport.new),
        TvBrand.samsung => SamsungDriver(device, keys, WebSocketTransport.new),
        TvBrand.samsungEncrypted =>
          SamsungEncryptedDriver(device, keys, WebSocketTransport.new, IoSamsungHttp()),
        TvBrand.fireTv => FireTvDriver(device, keys, TcpTransport.new),
        TvBrand.roku => RokuDriver(device, IoSamsungHttp()),
        TvBrand.samsungLegacy => SamsungLegacyDriver(device, TcpTransport.new),
      };
});

/// Sends a Wake-on-LAN packet; overridable in tests.
final wakeOnLanProvider = Provider<Future<void> Function(String mac, String host)>(
    (ref) => (mac, host) => sendWakeOnLan(mac, host: host));
