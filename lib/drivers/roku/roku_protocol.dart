import '../../core/tv_key.dart';
import '../../core/wake_on_lan.dart' show normalizeMac;

/// Roku's External Control Protocol (ECP): plain HTTP on port 8060, no pairing.
class RokuKeyMap {
  static String? key(TvKey k) => switch (k) {
        TvKey.up => 'Up',
        TvKey.down => 'Down',
        TvKey.left => 'Left',
        TvKey.right => 'Right',
        TvKey.ok => 'Select',
        TvKey.back => 'Back',
        TvKey.home => 'Home',
        TvKey.menu => 'Info', // the "*" options button
        TvKey.volumeUp => 'VolumeUp',
        TvKey.volumeDown => 'VolumeDown',
        TvKey.mute => 'VolumeMute',
        TvKey.channelUp => 'ChannelUp',
        TvKey.channelDown => 'ChannelDown',
        TvKey.rewind => 'Rev',
        TvKey.play => 'Play',
        TvKey.pause => 'Play', // Roku has a single play/pause toggle
        TvKey.fastForward => 'Fwd',
        TvKey.power => 'Power',
        TvKey.input => null,
      };
}

Uri rokuInfoUri(String host) => Uri.parse('http://$host:8060/query/device-info');

/// [key] must already be URL-safe (see [rokuLiteralKey]).
Uri rokuKeypressUri(String host, String key) => Uri.parse('http://$host:8060/keypress/$key');

/// Typing a character is a key named `Lit_<url-encoded character>`.
String rokuLiteralKey(String character) => 'Lit_${Uri.encodeComponent(character)}';

class RokuInfo {
  const RokuInfo({this.name, this.model, this.mac});
  final String? name;
  final String? model;
  final String? mac;
}

String? _tag(String xml, String name) {
  final m = RegExp('<$name>([^<]*)</$name>', caseSensitive: false).firstMatch(xml);
  if (m == null) return null;
  return m
      .group(1)!
      .trim()
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

/// Reads the interesting fields of a `/query/device-info` reply, or null if the
/// reply isn't one. The MAC is the one of the interface in use (Wi-Fi or Ethernet).
RokuInfo? parseRokuDeviceInfo(String xml) {
  if (!xml.contains('<device-info')) return null;
  final ethernet = _tag(xml, 'network-type')?.toLowerCase() == 'ethernet';
  final wifiMac = _mac(_tag(xml, 'wifi-mac'));
  final ethernetMac = _mac(_tag(xml, 'ethernet-mac'));
  return RokuInfo(
    name: _tag(xml, 'friendly-device-name') ?? _tag(xml, 'user-device-name'),
    model: _tag(xml, 'model-name'),
    mac: ethernet ? (ethernetMac ?? wifiMac) : (wifiMac ?? ethernetMac),
  );
}

String? _mac(String? raw) => raw == null ? null : normalizeMac(raw);
