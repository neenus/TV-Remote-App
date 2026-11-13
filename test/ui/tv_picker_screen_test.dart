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
}
