import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tv_remote/ui/widgets/hold_repeat.dart';

const box = Key('box');

Widget host(VoidCallback onFire) => MaterialApp(
    home: Center(
        child: HoldRepeat(
            onFire: onFire, child: const SizedBox(key: box, width: 100, height: 100))));

void main() {
  testWidgets('hold_repeat_fires_repeatedly_then_stops_on_release', (tester) async {
    var n = 0;
    await tester.pumpWidget(host(() => n++));
    final g = await tester.startGesture(tester.getCenter(find.byKey(box)));
    expect(n, 1);
    await tester.pump(const Duration(milliseconds: 760));
    expect(n, greaterThanOrEqualTo(3));
    await g.up();
    final afterRelease = n;
    await tester.pump(const Duration(seconds: 1));
    expect(n, afterRelease);
  });

  testWidgets('quick_tap_fires_once', (tester) async {
    var n = 0;
    await tester.pumpWidget(host(() => n++));
    await tester.tap(find.byKey(box));
    await tester.pump(const Duration(seconds: 1));
    expect(n, 1);
  });

  testWidgets('hold_repeat_stops_on_dispose', (tester) async {
    var n = 0;
    await tester.pumpWidget(host(() => n++));
    await tester.startGesture(tester.getCenter(find.byKey(box)));
    expect(n, 1);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 1));
    expect(n, 1);
  });
}
