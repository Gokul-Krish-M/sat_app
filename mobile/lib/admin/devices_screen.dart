import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../auth/session.dart';

/// Registered phones: mark 2-3 as shared (for staff without a phone),
/// or reset one when an employee changes their phone.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, required this.session});
  final Session session;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late Future<List<AppDevice>> _list;

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _list = _api.devices(); // no setState inside initState
  }

  void _load() => setState(() {
        _list = _api.devices();
      });

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _toggle(AppDevice d, bool shared) async {
    try {
      await _api.setDeviceShared(d.id, shared);
      _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _reset(AppDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Reset ${d.ownerName}\'s phone?'),
        content: const Text(
            'They will be logged out and can then log in on a new phone. '
            'Past attendance is kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.resetDevice(d.id);
      _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myDevice = widget.session.device?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Phones')),
      body: FutureBuilder(
        future: _list,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final devices = snap.data!;
          return RefreshIndicator(
            onRefresh: () async {
              _load();
              await _list;
            },
            child: ListView(children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Turn on "Shared" for the phones that staff without a phone '
                    'can use to clock in.'),
              ),
              for (final d in devices) ...[
                // One row per phone: owner + status on the left, its own
                // "Shared" switch and menu on the right of the same row.
                ListTile(
                  leading: Icon(d.isShared ? Icons.groups : Icons.phone_android,
                      color: d.isShared ? Colors.indigo : null),
                  title: Text(
                      '${d.ownerName}${d.ownerIsAdmin ? ' (Admin)' : ''}'
                      '${d.id == myDevice ? ' · this phone' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${d.ownerEmpCode} · ${d.isShared ? 'Shared' : 'Personal'}'
                    ' · since ${DateFormat.yMMMd().format(d.registeredAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(value: d.isShared, onChanged: (v) => _toggle(d, v)),
                    PopupMenuButton<String>(
                      enabled: d.id != myDevice,
                      onSelected: (_) => _reset(d),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'reset', child: Text('Reset phone')),
                      ],
                    ),
                  ]),
                ),
                const Divider(height: 1, indent: 72),
              ],
            ]),
          );
        },
      ),
    );
  }
}
