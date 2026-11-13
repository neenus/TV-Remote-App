import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/app.dart';

void main() {
  testWidgets('app builds', (tester) async {
    await tester.pumpWidget(const App());
    expect(find.text('TV Remote'), findsOneWidget);
  });
}
