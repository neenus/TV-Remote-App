import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tv_remote/core/fake_driver.dart';
import 'package:tv_remote/core/tv_driver.dart';
import 'package:tv_remote/core/tv_key.dart';
import 'package:tv_remote/ui/remote_screen.dart';
import 'package:tv_remote/ui/theme.dart';

class ThrowingDriver extends FakeDriver {
  @override
  Future<void> sendKey(TvKey key) async => throw const TvConnectionError();
}

Widget screen(FakeDriver d, {Future<void> Function()? onPower}) => MaterialApp(
    theme: auroraTheme(),
    home: RemoteScreen(driver: d, tvName: 'Living Room', onPower: onPower ?? () async {}));

Finder key(TvKey k) => find.byKey(ValueKey('key-${k.name}'));

void main() {
  testWidgets('tapping_volume_up_sends_volumeUp', (tester) async {
    final d = FakeDriver();
    await tester.pumpWidget(screen(d));
    await tester.ensureVisible(key(TvKey.volumeUp));
    await tester.tap(key(TvKey.volumeUp));
    await tester.pump();
    expect(d.sent, [TvKey.volumeUp]);
  });

  testWidgets('disabled_key_does_not_send', (tester) async {
    final d = FakeDriver(
        capabilities: TvCapabilities(TvKey.values.toSet()..remove(TvKey.menu)));
    await tester.pumpWidget(screen(d));
    await tester.ensureVisible(key(TvKey.menu));
    await tester.tap(key(TvKey.menu));
    await tester.pump();
    expect(d.sent, isEmpty);
  });

  testWidgets('power_button_calls_onPower', (tester) async {
    var called = false;
    await tester.pumpWidget(screen(FakeDriver(), onPower: () async => called = true));
    await tester.tap(key(TvKey.power));
    await tester.pump();
    expect(called, isTrue);
  });

  testWidgets('shows_tv_name', (tester) async {
    await tester.pumpWidget(screen(FakeDriver()));
    expect(find.text('LIVING ROOM'), findsOneWidget);
  });

  testWidgets('no_exception_when_driver_sendKey_throws', (tester) async {
    await tester.pumpWidget(screen(ThrowingDriver()));
    await tester.ensureVisible(key(TvKey.volumeUp));
    await tester.tap(key(TvKey.volumeUp));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  for (final k in [TvKey.rewind, TvKey.play, TvKey.pause, TvKey.fastForward]) {
    testWidgets('tapping_${k.name}_sends_${k.name}', (tester) async {
      final d = FakeDriver();
      await tester.pumpWidget(screen(d));
      await tester.ensureVisible(key(k));
      await tester.tap(key(k));
      await tester.pump();
      expect(d.sent, [k]);
    });
  }

  testWidgets('media_keys_are_disabled_when_the_tv_cannot_do_them', (tester) async {
    final d = FakeDriver(
        capabilities: TvCapabilities(TvKey.values.toSet()..remove(TvKey.play)));
    await tester.pumpWidget(screen(d));
    await tester.ensureVisible(key(TvKey.play));
    await tester.tap(key(TvKey.play));
    await tester.pump();
    expect(d.sent, isEmpty);
  });
}
