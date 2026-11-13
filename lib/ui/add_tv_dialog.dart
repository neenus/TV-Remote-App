import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../core/tv_device.dart';
import '../core/wake_on_lan.dart';
import '../discovery/lg_discovery.dart';

/// Asks for an IP (and optional MAC, used to wake the TV) and returns a device.
Future<TvDevice?> showAddTvDialog(BuildContext context) =>
    showDialog<TvDevice>(context: context, builder: (_) => const _AddTvDialog());

class _AddTvDialog extends StatefulWidget {
  const _AddTvDialog();
  @override
  State<_AddTvDialog> createState() => _AddTvDialogState();
}

class _AddTvDialogState extends State<_AddTvDialog> {
  final _ip = TextEditingController();
  final _mac = TextEditingController();
  String? _error;
  TvBrand _brand = TvBrand.lg;

  @override
  void dispose() {
    _ip.dispose();
    _mac.dispose();
    super.dispose();
  }

  void _submit() {
    final host = _ip.text.trim();
    if (host.isEmpty) {
      setState(() => _error = 'Enter the TV\'s IP address');
      return;
    }
    if (InternetAddress.tryParse(host) == null) {
      setState(() => _error = 'Enter a valid IP address');
      return;
    }
    final mac = _mac.text.trim();
    if (mac.isNotEmpty) {
      try {
        magicPacket(mac);
      } on FormatException {
        setState(() => _error = 'MAC should look like AA:BB:CC:DD:EE:FF');
        return;
      }
    }
    Navigator.pop(
        context, manualDevice(host, brand: _brand).copyWith(mac: mac.isEmpty ? null : mac));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add a TV'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 8, children: [
            for (final b in TvBrand.values)
              ChoiceChip(
                label: Text(brandLabel(b)),
                selected: _brand == b,
                onSelected: (_) => setState(() => _brand = b),
              ),
          ]),
          TextField(
              controller: _ip,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'IP address')),
          TextField(
              controller: _mac,
              decoration: const InputDecoration(
                  labelText: 'MAC address (optional, for power on)')),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: const Text('Connect')),
        ],
      );
}
