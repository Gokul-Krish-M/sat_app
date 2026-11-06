import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../clock/face_capture_screen.dart';
import '../widgets/auth_image.dart';

const _enrollPhotoCount = 3;

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key, required this.session});
  final Session session;

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  late Future<List<AppUser>> _list;
  bool _showInactive = false;

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _list = _api.employees(); // no setState inside initState
  }

  void _load() => setState(() {
        _list = _api.employees();
      });

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _addOrEdit([AppUser? existing]) async {
    final saved = await showDialog<AppUser>(
      context: context,
      builder: (_) => _EmployeeDialog(api: _api, existing: existing),
    );
    if (saved == null) return;
    _load();
    if (existing == null && saved.role == 'employee' && mounted) {
      final enrollNow = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Enroll ${saved.name}\'s face now?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Later')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Enroll')),
          ],
        ),
      );
      if (enrollNow == true) await _enroll(saved);
    }
  }

  Future<void> _enroll(AppUser u) async {
    final consent = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Consent'),
        content: Text(
            'Confirm that ${u.name} has agreed (in writing) to the use of their face photos '
            'for attendance. Photos are deleted when they leave.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmed')),
        ],
      ),
    );
    if (consent != true || !mounted) return;

    final result = await Navigator.of(context).push<CaptureResult>(MaterialPageRoute(
      builder: (_) => FaceCaptureScreen(enrollCount: _enrollPhotoCount, personName: u.name),
    ));
    if (result == null || !mounted) return;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      await _api.enroll(u.id, result.photos);
      if (mounted) _snack('${u.name} enrolled');
    } on ApiException catch (e) {
      if (mounted) _snack('Enrollment failed: ${e.message}. Please retake.');
    } finally {
      if (mounted) Navigator.of(context).pop();
      _load();
    }
  }

  Future<void> _remove(AppUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${u.name}?'),
        content: const Text(
            'They can no longer clock in. Their face data and photos are deleted. '
            'Past attendance records are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.removeEmployee(u.id);
      _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employees'),
        actions: [
          IconButton(
            tooltip: _showInactive ? 'Hide removed' : 'Show removed',
            icon: Icon(_showInactive ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _showInactive = !_showInactive),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEdit(),
        child: const Icon(Icons.person_add),
      ),
      body: FutureBuilder(
        future: _list,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final users = snap.data!.where((u) => _showInactive || u.active).toList();
          return RefreshIndicator(
            onRefresh: () async {
              _load();
              await _list;
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 80),
              children: [for (final u in users) _tile(u)],
            ),
          );
        },
      ),
    );
  }

  Widget _tile(AppUser u) {
    final tags = <String>[
      u.empCode,
      if (u.mobile != null) u.mobile!,
      if (u.isAdmin) 'Admin',
      if (!u.hasPhone) 'No phone (login blocked)',
      if (!u.active) 'Removed',
    ];
    return ListTile(
      enabled: u.active,
      leading: Avatar(_api, u.enrolled ? u.photoPath : null),
      title: Text(u.name),
      subtitle: Text(tags.join(' · ')),
      trailing: !u.active
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              if (!u.isAdmin)
                IconButton(
                  tooltip: u.enrolled ? 'Re-enroll face' : 'Enroll face',
                  icon: Icon(Icons.face,
                      color: u.enrolled ? Colors.green : Colors.orange),
                  onPressed: () => _enroll(u),
                ),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'edit' ? _addOrEdit(u) : _remove(u),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'remove', child: Text('Remove (left company)')),
                ],
              ),
            ]),
    );
  }
}

class _EmployeeDialog extends StatefulWidget {
  const _EmployeeDialog({required this.api, this.existing});
  final ApiClient api;
  final AppUser? existing;

  @override
  State<_EmployeeDialog> createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends State<_EmployeeDialog> {
  final _form = GlobalKey<FormState>();
  late final _mobile = TextEditingController(text: widget.existing?.mobile);
  late final _name = TextEditingController(text: widget.existing?.name);
  final _password = TextEditingController();
  late bool _hasPhone = widget.existing?.hasPhone ?? true;
  late bool _isAdmin = widget.existing?.isAdmin ?? false;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.existing != null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final pw = _password.text.isEmpty ? null : _password.text;
    final mobile = _mobile.text.trim().isEmpty ? null : _mobile.text.trim();
    try {
      final AppUser saved;
      if (_editing) {
        saved = await widget.api.updateEmployee(widget.existing!.id,
            name: _name.text.trim(), mobile: mobile, hasPhone: _hasPhone, password: pw);
      } else {
        saved = await widget.api.createEmployee(
          name: _name.text.trim(),
          mobile: mobile,
          hasPhone: _hasPhone,
          password: _hasPhone ? pw : null,
          role: _isAdmin ? 'admin' : 'employee',
        );
      }
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A password is kept when "Has own phone" is switched off, so switching it back
    // on only needs a new password if none was ever set.
    final needsPassword = _hasPhone && !(widget.existing?.hasPassword ?? false);
    return AlertDialog(
      title: Text(_editing ? 'Edit employee' : 'New employee'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.badge),
              title: Text(_editing ? widget.existing!.empCode : 'Auto-assigned'),
              subtitle: const Text('Employee number'),
            ),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            TextFormField(
              controller: _mobile,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: _hasPhone ? 'Mobile number (login)' : 'Mobile number (optional)',
              ),
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                if (digits.isEmpty) return _hasPhone ? 'Required' : null;
                if (digits.length < 10) return 'Enter a 10-digit number';
                return null;
              },
            ),
            if (!_isAdmin)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Has own phone'),
                subtitle: Text(_hasPhone
                    ? 'Logs in and clocks in on their own phone'
                    : 'Login blocked; clocks in on a shared phone'),
                value: _hasPhone,
                onChanged: (v) => setState(() => _hasPhone = v),
              ),
            if (!_editing)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Admin'),
                value: _isAdmin,
                onChanged: (v) => setState(() {
                  _isAdmin = v;
                  if (v) _hasPhone = true;
                }),
              ),
            if (_hasPhone)
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                    labelText: needsPassword ? 'Password' : 'New password (optional)'),
                validator: (v) {
                  final s = v ?? '';
                  if (needsPassword && s.length < 6) return 'At least 6 characters';
                  if (!needsPassword && s.isNotEmpty && s.length < 6) return 'At least 6 characters';
                  return null;
                },
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
