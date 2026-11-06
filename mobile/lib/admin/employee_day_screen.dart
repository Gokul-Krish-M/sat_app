import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../widgets/auth_image.dart';

/// All clock attempts (accepted and rejected) of one employee on one day,
/// with the selfies, for spot-checks.
class EmployeeDayScreen extends StatelessWidget {
  const EmployeeDayScreen({super.key, required this.api, required this.row, required this.day});
  final ApiClient api;
  final DayRow row;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${row.name} · ${DateFormat.yMMMd().format(day)}')),
      body: FutureBuilder(
        future: api.userEvents(row.userId, day),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final events = snap.data!;
          if (events.isEmpty) return const Center(child: Text('No clock-ins on this day.'));
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: events.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (_, i) => _EventTile(api: api, event: events[i]),
          );
        },
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.api, required this.event});
  final ApiClient api;
  final AttendanceEvent event;

  @override
  Widget build(BuildContext context) {
    final e = event;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: e.selfieUrl == null
            ? null
            : () => showDialog(
                context: context,
                builder: (_) => Dialog(child: AuthImage(api, e.selfieUrl, fit: BoxFit.contain))),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AuthImage(api, e.selfieUrl, size: 80)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(e.accepted ? Icons.check_circle : Icons.cancel,
                color: e.accepted ? Colors.green : Colors.red, size: 20),
            const SizedBox(width: 6),
            Text('${e.type}  ${DateFormat.jm().format(e.ts)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
          if (!e.accepted) const Text('Face did not match', style: TextStyle(color: Colors.red)),
          Text('Phone: ${e.deviceOwnerName}'),
          Text('Check: ${e.liveness.isEmpty ? '-' : e.liveness}'
              '${e.distance != null ? ' · match distance ${e.distance!.toStringAsFixed(2)}' : ''}',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    ]);
  }
}
