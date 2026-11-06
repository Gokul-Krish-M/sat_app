import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/models.dart';
import '../auth/session.dart';
import '../widgets/auth_image.dart';
import 'clock_flow.dart';

/// Employee home: one huge camera button, today's IN/OUT list, and — on a
/// shared phone — a second button to clock in staff who have no phone.
class EmployeeHome extends StatefulWidget {
  const EmployeeHome({super.key, required this.session});
  final Session session;

  @override
  State<EmployeeHome> createState() => _EmployeeHomeState();
}

class _EmployeeHomeState extends State<EmployeeHome> {
  List<AttendanceEvent> _today = [];

  @override
  void initState() {
    super.initState();
    ensureLocationPermission();
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.session.refresh(); // picks up "shared phone" changes
      final events = await widget.session.api.myToday();
      if (mounted) setState(() => _today = events);
    } catch (_) {}
  }

  Future<void> _clockSelf() async {
    await runClockFlow(context, widget.session.api);
    _load();
  }

  Future<void> _clockOther() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SharedStaffScreen(session: widget.session),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final user = s.user!;
    final nextIsIn = _today.isEmpty || _today.last.type == 'OUT';
    final shared = s.device?.isShared ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(user.name),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => _confirmLogout(context)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: 220,
              height: 220,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: nextIsIn ? Colors.green : Colors.orange,
                ),
                onPressed: user.enrolled ? _clockSelf : null,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.face, size: 96),
                  Icon(nextIsIn ? Icons.login : Icons.logout, size: 48),
                ]),
              ),
            ),
          ),
          if (!user.enrolled)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('Your face is not enrolled yet. Please see the admin.',
                  textAlign: TextAlign.center),
            ),
          if (shared) ...[
            const SizedBox(height: 24),
            Center(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
                icon: const Icon(Icons.groups, size: 40),
                label: const Text('Clock in someone else', style: TextStyle(fontSize: 18)),
                onPressed: _clockOther,
              ),
            ),
          ],
          const SizedBox(height: 32),
          for (final e in _today)
            ListTile(
              leading: Icon(e.type == 'IN' ? Icons.login : Icons.logout,
                  color: e.type == 'IN' ? Colors.green : Colors.orange, size: 32),
              title: Text(e.type, style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: Text(DateFormat.jm().format(e.ts), style: const TextStyle(fontSize: 18)),
            ),
        ]),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok == true) widget.session.logout();
  }
}

/// On a shared phone: pick a no-phone employee by photo, then hand them the phone.
class SharedStaffScreen extends StatefulWidget {
  const SharedStaffScreen({super.key, required this.session});
  final Session session;

  @override
  State<SharedStaffScreen> createState() => _SharedStaffScreenState();
}

class _SharedStaffScreenState extends State<SharedStaffScreen> {
  late Future<List<AppUser>> _staff = widget.session.api.sharedStaff();

  @override
  Widget build(BuildContext context) {
    final api = widget.session.api;
    return Scaffold(
      appBar: AppBar(title: const Text('Who is clocking in?')),
      body: FutureBuilder(
        future: _staff,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${snap.error}'),
                IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => setState(() {
                          _staff = api.sharedStaff();
                        })),
              ]),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final staff = snap.data!;
          if (staff.isEmpty) return const Center(child: Text('No staff without a phone.'));
          return GridView.count(
            padding: const EdgeInsets.all(16),
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: [
              for (final u in staff)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: u.enrolled ? () => runClockFlow(context, api, forUser: u) : null,
                    child: Column(children: [
                      Expanded(
                          child: SizedBox(
                              width: double.infinity, child: AuthImage(api, u.enrolled ? u.photoPath : null))),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(u.name,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
