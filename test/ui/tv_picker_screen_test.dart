import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_remote/app.dart';
import 'package:tv_remote/core/fake_driver.dart';
import 'package:tv_remote/core/key_store.dart';
import 'package:tv_remote/core/tv_device.dart';
import 'package:tv_remote/core/tv_driver.dart';
import 'package:tv_remote/core/tv_key.dart';
import 'package:tv_remote/discovery/discovery_state.dart';
import 'package:tv_remote/discovery/lg_discovery.dart';
import 'package:tv_remote/providers.dart';
import 'package:tv_remote/ui/remote_screen.dart';

const saved =
    TvDevice(id: 's1', name: 'Saved TV', brand: TvBrand.lg, host: '10.0.0.2');
const found =
    TvDevice(id: 'f1', name: 'Found TV', brand: TvBrand.lg, host: '10.0.0.3');

class ScriptedDriver extends FakeDriver {
  ScriptedDriver(this.script, {super.capabilities});
  final Future<void> Function(ScriptedDriver) script;
  @override
  Future<void> connect({bool pinPairing = false}) {
    lastPinPairing = pinPairing;
    return script(this);
  }
}

Future<Widget> app({
  List<TvDevice> savedTvs = const [],
  List<TvDevice> foundTvs = const [],
  TvDriver Function(TvDevice)? driver,
  Stream<TvDevice> Function()? rediscover,
  Stream<DiscoveryState>? discovery,
  KeyStore? keys,
  Future<void> Function(String, String)? wake,
}) async {
  SharedPreferences.setMockInitialValues({
    'saved_tvs': savedTvs.map((d) => jsonEncode(d.toJson())).toList(),
  });
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      if (keys != null) keyStoreProvider.overrideWithValue(keys),
      discoveredTvsProvider.overrideWith(
          (ref) => discovery ?? Stream.value(DiscoveryState(foundTvs))),
      driverFactoryProvider.overrideWithValue(driver ?? (_) => FakeDriver()),
      rediscoverProvider.overrideWithValue(rediscover ?? () => const Stream.empty()),
      wakeOnLanProvider.overrideWithValue(wake ?? (_, _) async {}),
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
        wake: (m, _) async => woken = m,
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

  testWidgets('pairing_defaults_to_an_on_screen_code', (tester) async {
    final d = ScriptedDriver((d) async {
      d.emit(const AwaitingPin());
      await Completer<void>().future;
    });
    await tester.pumpWidget(await app(savedTvs: [saved], driver: (_) => d));
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pump();
    await tester.pump();
    expect(d.lastPinPairing, isTrue);
    expect(find.text('Enter the code shown on your TV'), findsOneWidget);
  });

  testWidgets('can_switch_between_code_and_accept_pairing', (tester) async {
    final drivers = <ScriptedDriver>[];
    await tester.pumpWidget(await app(
        savedTvs: [saved],
        driver: (_) {
          final d = ScriptedDriver((d) async {
            d.emit(d.lastPinPairing ? const AwaitingPin() : const AwaitingPairing());
            await Completer<void>().future;
          });
          drivers.add(d);
          return d;
        }));
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Enter the code shown on your TV'), findsOneWidget);

    await tester.tap(find.text('Accept on the TV instead'));
    await tester.pump();
    await tester.pump();
    expect(drivers.length, 2);
    expect(drivers[1].lastPinPairing, isFalse);
    expect(find.text('Accept the prompt on your TV'), findsOneWidget);

    await tester.tap(find.text('No remote? Use a code instead'));
    await tester.pump();
    await tester.pump();
    expect(drivers.length, 3);
    expect(drivers[2].lastPinPairing, isTrue);
    expect(find.text('Enter the code shown on your TV'), findsOneWidget);
  });

  testWidgets('entering_the_code_pairs_and_opens_the_remote', (tester) async {
    late ScriptedDriver driver;
    await tester.pumpWidget(await app(
        savedTvs: [saved],
        driver: (_) => driver = ScriptedDriver((d) async {
              d.emit(const AwaitingPin());
              await d.pinSubmitted.future;
              d.emit(const Connected());
            })));
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), '12345678');
    await tester.tap(find.text('Pair'));
    await tester.pumpAndSettle();
    expect(driver.submittedPins, ['12345678']);
    expect(find.byType(RemoteScreen), findsOneWidget);
  });

  testWidgets('wrong_code_failure_says_the_code_was_not_accepted', (tester) async {
    await tester.pumpWidget(await app(
        savedTvs: [saved],
        driver: (_) => ScriptedDriver((d) async {
              d.emit(Failed(const PairingDenied('That code was not accepted')));
              throw const PairingDenied('That code was not accepted');
            })));
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pumpAndSettle();
    expect(find.text('That code was not accepted'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('code_screen_ignores_empty_input', (tester) async {
    final d = ScriptedDriver((d) async {
      d.emit(const AwaitingPin());
      await Completer<void>().future;
    });
    await tester.pumpWidget(await app(savedTvs: [saved], driver: (_) => d));
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Pair'));
    await tester.pump();
    expect(d.submittedPins, isEmpty);
  });

  group('scanning', () {
    testWidgets('shows_a_searching_state_while_scanning', (tester) async {
      final scan = StreamController<DiscoveryState>();
      addTearDown(scan.close);
      await tester.pumpWidget(await app(discovery: scan.stream));
      scan.add(const DiscoveryState([], scanning: true));
      await tester.pump();
      await tester.pump();
      expect(find.text('Searching for TVs on your Wi-Fi…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text('No TVs found. Enter an IP address.'), findsNothing);
    });

    testWidgets('shows_empty_message_only_after_the_scan_finishes', (tester) async {
      final scan = StreamController<DiscoveryState>();
      addTearDown(scan.close);
      await tester.pumpWidget(await app(discovery: scan.stream));
      scan.add(const DiscoveryState([], scanning: false));
      await tester.pump();
      await tester.pump();
      expect(find.text('No TVs found. Enter an IP address.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('lists_found_tvs_and_keeps_showing_progress_while_scanning',
        (tester) async {
      final scan = StreamController<DiscoveryState>();
      addTearDown(scan.close);
      await tester.pumpWidget(await app(discovery: scan.stream));
      scan.add(const DiscoveryState([found], scanning: true));
      await tester.pump();
      await tester.pump();
      expect(find.text('Found TV'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows_searching_before_the_first_result_arrives', (tester) async {
      final scan = StreamController<DiscoveryState>();
      addTearDown(scan.close);
      await tester.pumpWidget(await app(discovery: scan.stream));
      await tester.pump();
      expect(find.text('Searching for TVs on your Wi-Fi…'), findsOneWidget);
    });
  });

  testWidgets('add_dialog_lets_you_pick_samsung', (tester) async {
    TvDevice? created;
    await tester.pumpWidget(await app(driver: (d) {
      created = d;
      return FakeDriver();
    }));
    await tester.pump();
    await tester.tap(find.text('Add by IP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Samsung (2016 or newer)'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '10.0.0.8');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(created?.brand, TvBrand.samsung);
    expect(created?.host, '10.0.0.8');
    expect(find.byType(RemoteScreen), findsOneWidget);
  });

  testWidgets('add_dialog_defaults_to_lg', (tester) async {
    TvDevice? created;
    await tester.pumpWidget(await app(driver: (d) {
      created = d;
      return FakeDriver();
    }));
    await tester.pump();
    await tester.tap(find.text('Add by IP'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '10.0.0.8');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(created?.brand, TvBrand.lg);
  });

  testWidgets('add_dialog_offers_older_samsung', (tester) async {
    TvDevice? created;
    await tester.pumpWidget(await app(driver: (d) {
      created = d;
      return FakeDriver();
    }));
    await tester.pump();
    await tester.tap(find.text('Add by IP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Samsung (2013 or older)'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '10.0.0.7');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(created?.brand, TvBrand.samsungLegacy);
    expect(find.byType(RemoteScreen), findsOneWidget);
  });

  testWidgets('add_dialog_offers_2014_2015_samsung', (tester) async {
    TvDevice? created;
    await tester.pumpWidget(await app(driver: (d) {
      created = d;
      return FakeDriver();
    }));
    await tester.pump();
    await tester.tap(find.text('Add by IP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Samsung (2014-2015)'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '10.0.0.9');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(created?.brand, TvBrand.samsungEncrypted);
  });

  testWidgets('forgetting_a_tv_also_deletes_its_saved_pairing', (tester) async {
    final store = MemoryKeyStore();
    await store.write('s1', 'saved-pairing');
    await tester.pumpWidget(await app(savedTvs: [saved], keys: store));
    await tester.pump();
    await tester.tap(find.byTooltip('Forget'));
    await tester.pumpAndSettle();
    expect(find.text('Saved TV'), findsNothing);
    expect(await store.read('s1'), isNull);
  });

  testWidgets('a_code_only_tv_has_no_accept_on_the_tv_switch', (tester) async {
    final d = ScriptedDriver((d) async {
      d.emit(const AwaitingPin());
      await Completer<void>().future;
    }, capabilities: TvCapabilities(TvKey.values.toSet(), pairingChoice: false));
    await tester.pumpWidget(await app(savedTvs: [saved], driver: (_) => d));
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Enter the code shown on your TV'), findsOneWidget);
    expect(find.text('Accept on the TV instead'), findsNothing);
  });

  testWidgets('the_code_box_accepts_digits_only', (tester) async {
    late ScriptedDriver driver;
    await tester.pumpWidget(await app(
        savedTvs: [saved],
        driver: (_) => driver = ScriptedDriver((d) async {
              d.emit(const AwaitingPin());
              await Completer<void>().future;
            })));
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'a1 b2');
    await tester.tap(find.text('Pair'));
    await tester.pump();
    expect(driver.submittedPins, ['12']);
  });

  testWidgets('the_code_box_is_empty_after_retrying', (tester) async {
    var n = 0;
    await tester.pumpWidget(await app(
        savedTvs: [saved],
        driver: (_) {
          n++;
          return ScriptedDriver((d) async {
            d.emit(const AwaitingPin());
            if (n == 1) {
              await d.pinSubmitted.future;
              throw const PairingDenied('That code was not accepted');
            }
            await Completer<void>().future;
          });
        }));
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Pair'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('add_dialog_offers_fire_tv', (tester) async {
    TvDevice? created;
    await tester.pumpWidget(await app(driver: (d) {
      created = d;
      return FakeDriver();
    }));
    await tester.pump();
    await tester.tap(find.text('Add by IP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fire TV'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '10.0.0.8');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(created?.brand, TvBrand.fireTv);
  });

  testWidgets('a_pairing_note_from_the_driver_is_shown_while_waiting', (tester) async {
    final d = ScriptedDriver((d) async {
      d.emit(const AwaitingPairing());
      await Completer<void>().future;
    }, capabilities: TvCapabilities(TvKey.values.toSet(), pairingNote: 'Tick Always allow.'));
    await tester.pumpWidget(await app(savedTvs: [saved], driver: (_) => d));
    await tester.pump();
    await tester.tap(find.text('Saved TV'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Accept the prompt on your TV'), findsOneWidget);
    expect(find.text('Tick Always allow.'), findsOneWidget);
  });

  testWidgets('a_tv_added_by_ip_is_not_searched_for_when_it_cannot_be_reached',
      (tester) async {
    var scans = 0;
    await tester.pumpWidget(await app(
        savedTvs: [manualDevice('10.0.0.8')],
        rediscover: () {
          scans++;
          return const Stream.empty();
        },
        driver: (_) => ScriptedDriver((d) async => throw const TvConnectionError())));
    await tester.pump();
    await tester.tap(find.textContaining('10.0.0.8').first);
    await tester.pumpAndSettle();
    expect(scans, 0, reason: 'a manually added TV cannot be re-found by the scan');
    expect(find.text('Retry'), findsOneWidget);
  });
}
