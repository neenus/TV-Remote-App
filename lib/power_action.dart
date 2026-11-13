import 'core/tv_device.dart';
import 'core/tv_driver.dart';
import 'core/tv_key.dart';
import 'core/wake_on_lan.dart';

/// Sends a wake-up signal for a TV with this MAC address, at this address.
typedef WakeFn = Future<void> Function(String mac, String host);

Future<void> _defaultWake(String mac, String host) => sendWakeOnLan(mac, host: host);

/// Power toggles the TV when reachable. If the TV can't be reached (it is off
/// or asleep) it falls back to Wake-on-LAN using the saved MAC address.
Future<void> handlePower({
  required TvDevice device,
  required TvDriver driver,
  WakeFn wake = _defaultWake,
}) async {
  try {
    await driver.sendKey(TvKey.power);
  } on TvConnectionError {
    final mac = device.mac;
    if (mac == null) {
      throw const TvConnectionError(
          'TV unreachable. No MAC saved; power on the TV once or add its MAC address.');
    }
    await wake(mac, device.host);
  }
}
