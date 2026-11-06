import 'package:attendance_app/api/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DaySummary parses the /admin/attendance response', () {
    final s = DaySummary.fromJson({
      'date': '2026-11-05',
      'present': 1,
      'absent': 0,
      'still_in': 1,
      'rows': [
        {
          'user_id': 3, 'emp_code': 'E3', 'name': 'Chitra', 'has_phone': false,
          'in_time': '2026-11-05T09:02:00+05:30', 'out_time': null, 'hours': null,
          'status': 'still_in', 'in_device_owner': 'Asha', 'out_device_owner': '',
          'in_via_other_phone': true, 'out_via_other_phone': false,
          'photo_url': '/users/3/photo',
        }
      ],
    });
    final r = s.rows.single;
    expect(r.status, 'still_in');
    expect(r.inViaOtherPhone, isTrue);
    expect(r.inTime!.toUtc(), DateTime.utc(2026, 11, 5, 3, 32));
    expect(r.inTime!.isUtc, isFalse); // converted to phone local time for display
  });
}
