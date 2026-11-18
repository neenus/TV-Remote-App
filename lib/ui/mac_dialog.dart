import 'package:material_ui/material_ui.dart';

import '../core/wake_on_lan.dart';

/// Asks for a TV's MAC address (used to turn it on). Returns the normalised
/// address, or null if cancelled.
Future<String?> showMacDialog(BuildContext context, {String? current}) =>
    showDialog<String>(context: context, builder: (_) => _MacDialog(current: current));

class _MacDialog extends StatefulWidget {
  const _MacDialog({this.current});
  final String? current;
  @override
  State<_MacDialog> createState() => _MacDialogState();
}

class _MacDialogState extends State<_MacDialog> {
  late final _controller = TextEditingController(text: widget.current ?? '');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final mac = normalizeMac(_controller.text);
    if (mac == null) {
      setState(() => _error = 'MAC should look like AA:BB:CC:DD:EE:FF');
      return;
    }
    Navigator.pop(context, mac);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('MAC address'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Used to turn the TV on. Find it on the TV (Settings, About / Network status) '
              'or in your router\'s list of connected devices.',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            decoration: InputDecoration(labelText: 'AA:BB:CC:DD:EE:FF', errorText: _error),
            onSubmitted: (_) => _save(),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      );
}
