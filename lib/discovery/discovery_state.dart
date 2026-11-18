import '../core/tv_device.dart';

/// TVs found so far, and whether the network scan is still running.
class DiscoveryState {
  const DiscoveryState(this.tvs, {this.scanning = false});
  final List<TvDevice> tvs;
  final bool scanning;
}
