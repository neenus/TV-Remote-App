import 'package:material_ui/material_ui.dart';

import 'ui/theme.dart';
import 'ui/tv_picker_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'TV Remote',
        theme: auroraTheme(),
        debugShowCheckedModeBanner: false,
        home: const TvPickerScreen(),
      );
}
