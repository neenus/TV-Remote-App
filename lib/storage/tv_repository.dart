import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/tv_device.dart';

class TvRepository {
  TvRepository(this._prefs);
  final SharedPreferences _prefs;
  static const _key = 'saved_tvs';

  List<TvDevice> all() {
    final result = <TvDevice>[];
    for (final s in _prefs.getStringList(_key) ?? const <String>[]) {
      try {
        result.add(TvDevice.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // A corrupt entry must not break the whole picker.
      }
    }
    return result;
  }

  Future<void> _write(List<TvDevice> list) => _prefs.setStringList(
      _key, list.map((d) => jsonEncode(d.toJson())).toList());

  Future<void> save(TvDevice d) async {
    final list = all()..removeWhere((x) => x.id == d.id);
    await _write([...list, d]);
  }

  Future<void> remove(String id) async =>
      _write(all()..removeWhere((x) => x.id == id));

  Future<TvDevice> refreshHost(TvDevice d, Stream<TvDevice> found) async {
    await for (final f in found) {
      if (f.id == d.id) return d.copyWith(host: f.host);
    }
    return d;
  }
}
