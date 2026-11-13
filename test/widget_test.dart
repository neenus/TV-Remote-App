import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_remote/app.dart';
import 'package:tv_remote/providers.dart';

void main() {
  testWidgets('app builds and shows the TV picker', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      discoveredTvsProvider.overrideWith((ref) => Stream.value([])),
    ], child: const App()));
    await tester.pump();
    expect(find.text('Your TVs'), findsOneWidget);
  });
}
