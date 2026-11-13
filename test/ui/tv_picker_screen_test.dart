import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_remote/app.dart';
import 'package:tv_remote/core/fake_driver.dart';
import 'package:tv_remote/core/tv_device.dart';
import 'package:tv_remote/core/tv_driver.dart';
import 'package:tv_remote/discovery/lg_discovery.dart';
import 'package:tv_remote/providers.dart';
import 'package:tv_remote/ui/remote_screen.dart';

const saved =
    TvDevice(id: 's1', name: 'Saved TV', brand: TvBrand.lg, host: '10.0.0.2');
const found =
    TvDevice(id: 'f1', name: 'Found TV', brand: TvBrand.lg, host: '10.0.0.3');

class ScriptedDriver extends FakeDriver {
  ScriptedDriver(this.script);
  final Future<void> Function(ScriptedDriver) script;
  @override
  Future<void> connect() => script(this);
}

Future<Widget> app({
  List<TvDevice> savedTvs = const [],
  List<TvDevice> foundTvs = const [],
  TvDriver Function(TvDevice)? driver,
  Stream<TvDevice> Function()? rediscover,
  Future<void> Function(String)? wake,
}) async {
  SharedPreferences.setMockInitialValues({
    'saved_tvs': savedTvs.map((d) => jsonEncode(d.toJson())).toList(),
  });
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      discoveredTvsProvider.overrideWith((ref) => Stream.value(foundTvs)),
      driverFactoryProvider.overrideWithValue(driver ?? (_) => FakeDriver()),
      rediscoverProvider.overrideWithValue(rediscover ?? () => const Stream.empty()),
      wakeOnLanProvider.overrideWithValue(wake ?? (_) async {}),
    ],
    child: const App(),
  );
}

void main() {
  testWidgets('picker_shows_empty_state_when_nothing_found', (tester) async {
    await tester.pumpWidget(await app());
    await tester.pump();
    expect(find.text('No TVs found. Enter an IP address.'), findsOneWidget);
  });

  testWidgets('picker_lists_saved_and_discovered_tvs', (tester) async {
    await tester.pumpWidget(await app(savedTvs: [saved], foundTvs: [found]));
    await tester.pump();
    expect(find.text('Saved TV'), findsOneWidget);
    expect(find.text('Found TV'), findsOneWidget);
  });

  testWidgets('picker_hides_discovered_tv_already_saved', (tester) async {
    await tester.pumpWidget(await app(savedTvs: [saved], foundTvs: [saved]));
    await tester.pump();
    expect(find.text('Saved TV'), findsOneWidget);
  });

  testWidgets('selecting_tv_with_denied_pairing_shows_retry', (tester) async {
    await tester.pumpWidget(await app(
        savedTvs: [saved],
        driver: (_) => ScriptedDriver((d) async {
              d.emit(Failed(const PairingDenied()));
              throw const PairingDenied();
            })));
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('app_flow_pairs_and_opens_remote', (tester) async {
    final gate = Completer<void>();
    await tester.pumpWidget(await app(
        savedTvs: [saved],
        driver: (_) => ScriptedDriver((d) async {
              d.emit(const AwaitingPairing());
              await gate.future;
              d.emit(const Connected());
            })));
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Accept the prompt on your TV'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(RemoteScreen), findsOneWidget);
  });

  testWidgets('manual_entry_adds_tv_and_opens_remote', (tester) async {
    await tester.pumpWidget(await app());
    await tester.pump();
    await tester.tap(find.text('Add by IP'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '10.0.0.5');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.byType(RemoteScreen), findsOneWidget);
  });

  testWidgets('picker_hides_discovered_tv_with_same_host_as_saved_manual_tv',
      (tester) async {
    final manual = manualDevice('10.0.0.3');
    await tester.pumpWidget(await app(savedTvs: [manual], foundTvs: [found]));
    await tester.pump();
    expect(find.text('Found TV'), findsNothing);
    expect(find.text(manual.name), findsOneWidget);
  });

  testWidgets('unreachable_tv_with_saved_mac_offers_turn_on', (tester) async {
    String? woken;
    const withMac = TvDevice(
        id: 's1', name: 'Saved TV', brand: TvBrand.lg, host: '10.0.0.2', mac: 'AA:BB:CC:DD:EE:FF');
    await tester.pumpWidget(await app(
        savedTvs: [withMac],
        wake: (m) async => woken = m,
        driver: (_) => ScriptedDriver((d) async => throw const TvConnectionError())));
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on TV'));
    await tester.pump();
    expect(woken, 'AA:BB:CC:DD:EE:FF');
  });

  testWidgets('unreachable_tv_without_mac_has_no_turn_on', (tester) async {
    await tester.pumpWidget(await app(
        savedTvs: [saved],
        driver: (_) => ScriptedDriver((d) async => throw const TvConnectionError())));
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Turn on TV'), findsNothing);
  });

  testWidgets('shows_searching_while_looking_for_moved_tv', (tester) async {
    final scan = StreamController<TvDevice>();
    await tester.pumpWidget(await app(
        savedTvs: [saved],
        rediscover: () => scan.stream,
        driver: (_) => ScriptedDriver((d) async => throw const TvConnectionError())));
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Searching for your TV…'), findsOneWidget);
    await scan.close();
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('retry_connects_again_and_searches_again', (tester) async {
    var created = 0, scans = 0;
    await tester.pumpWidget(await app(
        savedTvs: [saved],
        rediscover: () {
          scans++;
          return const Stream.empty();
        },
        driver: (_) {
          created++;
          return ScriptedDriver((d) async => throw const TvConnectionError());
        }));
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(created, 2);
    expect(scans, 2);
  });

  testWidgets('add_dialog_rejects_non_ip_and_uses_decimal_keyboard', (tester) async {
    await tester.pumpWidget(await app());
    await tester.pump();
    await tester.tap(find.text('Add by IP'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.keyboardType.decimal, isTrue);
    await tester.enterText(find.byType(TextField).first, 'not-an-ip');
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.text('Enter a valid IP address'), findsOneWidget);
    expect(find.byType(RemoteScreen), findsNothing);
  });

  testWidgets('learns_and_saves_mac_after_connecting', (tester) async {
    final driver = FakeDriver()..mac = 'AA:BB:CC:DD:EE:FF';
    await tester.pumpWidget(await app(savedTvs: [saved], driver: (_) => driver));
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pumpAndSettle();
    final repo = ProviderScope.containerOf(tester.element(find.byType(RemoteScreen)))
        .read(tvRepositoryProvider);
    expect(repo.all().single.mac, 'AA:BB:CC:DD:EE:FF');
  });

  testWidgets('does_not_ask_for_mac_when_already_saved', (tester) async {
    final driver = FakeDriver()..mac = 'FF:FF:FF:FF:FF:FF';
    const withMac = TvDevice(
        id: 's1', name: 'Saved TV', brand: TvBrand.lg, host: '10.0.0.2', mac: 'AA:BB:CC:DD:EE:FF');
    await tester.pumpWidget(await app(savedTvs: [withMac], driver: (_) => driver));
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pumpAndSettle();
    expect(driver.macFetches, 0);
  });

  testWidgets('missing_mac_does_not_break_the_remote', (tester) async {
    await tester.pumpWidget(await app(savedTvs: [saved])); // FakeDriver.mac == null
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pumpAndSettle();
    expect(find.byType(RemoteScreen), findsOneWidget);
    final repo = ProviderScope.containerOf(tester.element(find.byType(RemoteScreen)))
        .read(tvRepositoryProvider);
    expect(repo.all().single.mac, isNull);
  });
}
