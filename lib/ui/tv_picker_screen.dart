import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/tv_device.dart';
import '../discovery/discovery_state.dart';
import '../providers.dart';
import 'add_tv_dialog.dart';
import 'aurora_background.dart';
import 'glass_panel.dart';
import 'theme.dart';
import 'tv_session.dart';

class TvPickerScreen extends ConsumerStatefulWidget {
  const TvPickerScreen({super.key});
  @override
  ConsumerState<TvPickerScreen> createState() => _TvPickerScreenState();
}

class _TvPickerScreenState extends ConsumerState<TvPickerScreen> {
  void _open(TvDevice d) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => TvSession(device: d)))
      .then((_) => setState(() {}));

  Future<void> _add() async {
    final d = await showAddTvDialog(context);
    if (d != null && mounted) _open(d);
  }

  Widget _tile(TvDevice d, {bool saved = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GestureDetector(
          onTap: () => _open(d),
          child: GlassPanel(
            radius: 20,
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              const Icon(Icons.tv, color: AuroraColors.lilac),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.name, style: const TextStyle(fontSize: 16)),
                  Text(d.host,
                      style: const TextStyle(color: AuroraColors.textSecondary, fontSize: 12)),
                ]),
              ),
              if (saved)
                IconButton(
                  tooltip: 'Forget',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () async {
                    await ref.read(tvRepositoryProvider).remove(d.id);
                    if (mounted) setState(() {});
                  },
                ),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final savedTvs = ref.read(tvRepositoryProvider).all();
    final savedIds = savedTvs.map((d) => d.id).toSet();
    final savedHosts = savedTvs.map((d) => d.host).toSet();
    // A TV added by IP has a different id than its SSDP uuid, so match on host too.
    final discovery = ref.watch(discoveredTvsProvider).value ??
        const DiscoveryState([], scanning: true);
    final found = discovery.tvs
        .where((d) => !savedIds.contains(d.id) && !savedHosts.contains(d.host))
        .toList();
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(
                    child: Text('Your TVs',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600))),
                if (discovery.scanning)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  IconButton(
                      tooltip: 'Rescan',
                      onPressed: () => ref.invalidate(discoveredTvsProvider),
                      icon: const Icon(Icons.refresh)),
              ]),
              const SizedBox(height: 16),
              Expanded(
                child: (savedTvs.isEmpty && found.isEmpty)
                    ? Center(
                        child: discovery.scanning
                            ? const Column(mainAxisSize: MainAxisSize.min, children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 20),
                                Text('Searching for TVs on your Wi-Fi…',
                                    style: TextStyle(color: AuroraColors.textSecondary)),
                              ])
                            : const Text('No TVs found. Enter an IP address.',
                                style: TextStyle(color: AuroraColors.textSecondary)))
                    : ListView(children: [
                        for (final d in savedTvs) _tile(d, saved: true),
                        for (final d in found) _tile(d),
                      ]),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: const Text('Add by IP')),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
