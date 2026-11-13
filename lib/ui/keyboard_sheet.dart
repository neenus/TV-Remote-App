import 'package:material_ui/material_ui.dart';

import 'text_diff.dart';
import 'theme.dart';

/// A text box that mirrors what you type into the TV's focused text field.
class KeyboardSheet extends StatefulWidget {
  const KeyboardSheet({
    super.key,
    required this.onInsert,
    required this.onDelete,
    required this.onEnter,
    this.showHint = false,
  });

  final void Function(String text) onInsert;
  final void Function(int count) onDelete;
  final VoidCallback onEnter;

  /// Shown when the TV hasn't reported a text field (typing may not reach it).
  final bool showHint;

  @override
  State<KeyboardSheet> createState() => _KeyboardSheetState();
}

class _KeyboardSheetState extends State<KeyboardSheet> {
  final _controller = TextEditingController();
  String _last = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changed(String next) {
    final d = diffText(_last, next);
    _last = next;
    if (d.deleted > 0) widget.onDelete(d.deleted);
    if (d.inserted.isNotEmpty) widget.onInsert(d.inserted);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: AuroraColors.deepViolet,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Type on your TV',
                style: TextStyle(fontSize: 16, color: AuroraColors.textSecondary)),
            if (widget.showHint) ...[
              const SizedBox(height: 8),
              const Text(
                "The TV hasn't reported a text field. Some apps draw their own keyboard, "
                'and typing here may not reach them; use the d-pad on the TV\'s keyboard instead.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AuroraColors.magenta),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: _changed,
              onSubmitted: (_) => widget.onEnter(),
              decoration: const InputDecoration(hintText: 'Type here'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: FilledButton(onPressed: widget.onEnter, child: const Text('Enter'))),
              const SizedBox(width: 12),
              TextButton(
                  onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ]),
          ]),
        ),
      );
}
