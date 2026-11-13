import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tv_remote/ui/aurora_background.dart';
import 'package:tv_remote/ui/glass_panel.dart';
import 'package:tv_remote/ui/theme.dart';

void main() {
  testWidgets('glass_panel_renders_child_with_backdrop_filter', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: auroraTheme(),
        home: const Scaffold(body: GlassPanel(child: Text('x')))));
    expect(find.text('x'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('aurora_background_wraps_child', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: auroraTheme(),
        home: const AuroraBackground(child: Text('y'))));
    expect(find.text('y'), findsOneWidget);
  });

  test('theme_is_dark_and_uses_deep_navy', () {
    final t = auroraTheme();
    expect(t.brightness, Brightness.dark);
    expect(t.scaffoldBackgroundColor, AuroraColors.deepNavy);
  });
}
