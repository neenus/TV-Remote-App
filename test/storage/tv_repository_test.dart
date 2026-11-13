import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_remote/core/tv_device.dart';
import 'package:tv_remote/storage/tv_repository.dart';

const a = TvDevice(id: 'a', name: 'A', brand: TvBrand.lg, host: '1.1.1.1');

void main() {
  late TvRepository repo;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = TvRepository(await SharedPreferences.getInstance());
  });

  test('repository_saves_and_lists_devices', () async {
    await repo.save(a);
    expect(repo.all().map((d) => d.id), ['a']);
  });

  test('repository_save_replaces_same_id', () async {
    await repo.save(a);
    await repo.save(a.copyWith(host: '2.2.2.2'));
    expect(repo.all().length, 1);
    expect(repo.all().first.host, '2.2.2.2');
  });

  test('repository_removes_device', () async {
    await repo.save(a);
    await repo.remove('a');
    expect(repo.all(), isEmpty);
  });

  test('refresh_host_updates_changed_ip', () async {
    final found = Stream.value(a.copyWith(host: '3.3.3.3'));
    final r = await repo.refreshHost(a, found);
    expect(r.host, '3.3.3.3');
  });

  test('refresh_host_keeps_host_when_not_found', () async {
    final found = Stream.value(
        const TvDevice(id: 'other', name: 'O', brand: TvBrand.lg, host: '9.9.9.9'));
    final r = await repo.refreshHost(a, found);
    expect(r.host, '1.1.1.1');
  });

  test('repository_skips_corrupt_entries', () async {
    SharedPreferences.setMockInitialValues({
      'saved_tvs': [
        'not json',
        '{"id":"x","name":"X","brand":"nope","host":"h"}',
        '{"id":"a","name":"A","brand":"lg","host":"1.1.1.1"}',
      ]
    });
    repo = TvRepository(await SharedPreferences.getInstance());
    expect(repo.all().map((d) => d.id), ['a']);
  });
}
