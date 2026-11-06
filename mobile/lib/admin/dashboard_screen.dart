import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../widgets/auth_image.dart';
import 'employee_day_screen.dart';

/// Who came today / yesterday / any date, plus CSV download.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.session});
  final Session session;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime _day = _dateOnly(DateTime.now());
  Future<DaySummary>? _summary;
  bool _exporting = false;

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _summary = _api.daySummary(_day); // no setState inside initState
  }

  void _load() => setState(() {
        _summary = _api.daySummary(_day);
      });

  void _setDay(DateTime d) {
    _day = _dateOnly(d);
    _load();
  }

  DateTime get _today => _dateOnly(DateTime.now());
  DateTime get _yesterday => _today.subtract(const Duration(days: 1));

  Future<void> _pickDay() async {
    final d = await showDatePicker(
        context: context, initialDate: _day, firstDate: DateTime(2024), lastDate: _today);
    if (d != null) _setDay(d);
  }

  Future<void> _exportCsv() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: _today,
      initialDateRange: DateTimeRange(start: DateTime(_today.year, _today.month, 1), end: _today),
      helpText: 'Select dates for CSV',
    );
    if (range == null) return;
    setState(() => _exporting = true);
    try {
      final (name, bytes) = await _api.attendanceCsv(range.start, range.end);
      final file = File('${(await getTemporaryDirectory()).path}/$name');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: name,
      ));
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          IconButton(
            tooltip: 'Download CSV',
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            onPressed: _exporting ? null : _exportCsv,
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => widget.session.logout(),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Wrap(spacing: 8, children: [
            ChoiceChip(
                label: const Text('Today'),
                selected: _day == _today,
                onSelected: (_) => _setDay(_today)),
            ChoiceChip(
                label: const Text('Yesterday'),
                selected: _day == _yesterday,
                onSelected: (_) => _setDay(_yesterday)),
            ActionChip(
              avatar: const Icon(Icons.calendar_month, size: 18),
              label: Text(_day == _today || _day == _yesterday
                  ? 'Pick date'
                  : DateFormat.yMMMd().format(_day)),
              onPressed: _pickDay,
            ),
          ]),
        ),
        Expanded(
          child: FutureBuilder<DaySummary>(
            future: _summary,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${snap.error}'),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ]),
                );
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final s = snap.data!;
              return RefreshIndicator(
                onRefresh: () async {
                  _load();
                  await _summary;
                },
                child: ListView(children: [
                  _SummaryBar(summary: s),
                  for (final r in s.rows) _row(r),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _row(DayRow r) {
    final t = DateFormat.jm();
    final (color, label) = switch (r.status) {
      'present' => (Colors.green, 'Present'),
      'still_in' => (Colors.blue, 'Still in'),
      _ => (Colors.red, 'Absent'),
    };
    final subtitle = <String>[
      if (r.inTime != null) 'IN ${t.format(r.inTime!)}${r.inViaOtherPhone ? ' (via ${r.inDeviceOwner}\'s phone)' : ''}',
      if (r.outTime != null) 'OUT ${t.format(r.outTime!)}${r.outViaOtherPhone ? ' (via ${r.outDeviceOwner}\'s phone)' : ''}',
    ];
    return ListTile(
      leading: Avatar(_api, r.photoUrl, size: 44),
      title: Text(r.name),
      subtitle: subtitle.isEmpty ? Text(r.empCode) : Text(subtitle.join('\n')),
      isThreeLine: subtitle.length > 1,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Chip(
            label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
            backgroundColor: color,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
          if (r.hours != null) Text('${r.hours!.toStringAsFixed(1)} h'),
        ],
      ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EmployeeDayScreen(api: _api, row: r, day: _day),
      )),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.summary});
  final DaySummary summary;

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, int n, Color c) => Expanded(
          child: Card(
            color: c.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Text('$n', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c)),
                Text(label),
              ]),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(children: [
        tile('Present', summary.present, Colors.green),
        tile('Absent', summary.absent, Colors.red),
        tile('Still in', summary.stillIn, Colors.blue),
      ]),
    );
  }
}
