DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

class AppUser {
  final int id;
  final String empCode;
  final String name;
  final String? mobile;
  final String role;
  final bool hasPhone;
  final bool active;
  final bool enrolled;
  final bool hasPassword;

  AppUser.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        empCode = j['emp_code'],
        name = j['name'],
        mobile = j['mobile'],
        role = j['role'],
        hasPhone = j['has_phone'],
        active = j['active'],
        enrolled = j['enrolled'] ?? false,
        hasPassword = j['has_password'] ?? false;

  bool get isAdmin => role == 'admin';
  String get photoPath => '/users/$id/photo';
}

class AppDevice {
  final int id;
  final bool isShared;
  final int ownerUserId;
  final String ownerName;
  final String ownerEmpCode;
  final bool ownerIsAdmin;
  final DateTime registeredAt;

  AppDevice.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        isShared = j['is_shared'],
        ownerUserId = j['owner_user_id'],
        ownerName = j['owner_name'] ?? '',
        ownerEmpCode = j['owner_emp_code'] ?? '',
        ownerIsAdmin = j['owner_is_admin'] ?? false,
        registeredAt = DateTime.parse(j['registered_at']).toLocal();
}

class ClockResult {
  final bool accepted;
  final String? type; // IN / OUT
  final DateTime? ts;
  final String employeeName;
  final String message;

  ClockResult.fromJson(Map<String, dynamic> j)
      : accepted = j['accepted'],
        type = j['type'],
        ts = _dt(j['ts']),
        employeeName = j['employee_name'],
        message = j['message'];
}

class AttendanceEvent {
  final int id;
  final String type;
  final String status;
  final DateTime ts;
  final double? distance;
  final String liveness;
  final String deviceOwnerName;
  final String clockedByName;
  final String? selfieUrl;

  AttendanceEvent.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        type = j['type'],
        status = j['status'],
        ts = DateTime.parse(j['ts']).toLocal(),
        distance = (j['distance'] as num?)?.toDouble(),
        liveness = j['liveness'] ?? '',
        deviceOwnerName = j['device_owner_name'] ?? '',
        clockedByName = j['clocked_by_name'] ?? '',
        selfieUrl = j['selfie_url'];

  bool get accepted => status == 'accepted';
}

class DayRow {
  final int userId;
  final String empCode;
  final String name;
  final bool hasPhone;
  final DateTime? inTime;
  final DateTime? outTime;
  final double? hours;
  final String status; // present / absent / still_in
  final String inDeviceOwner;
  final String outDeviceOwner;
  final bool inViaOtherPhone;
  final bool outViaOtherPhone;
  final String? photoUrl;

  DayRow.fromJson(Map<String, dynamic> j)
      : userId = j['user_id'],
        empCode = j['emp_code'],
        name = j['name'],
        hasPhone = j['has_phone'],
        inTime = _dt(j['in_time']),
        outTime = _dt(j['out_time']),
        hours = (j['hours'] as num?)?.toDouble(),
        status = j['status'],
        inDeviceOwner = j['in_device_owner'] ?? '',
        outDeviceOwner = j['out_device_owner'] ?? '',
        inViaOtherPhone = j['in_via_other_phone'] ?? false,
        outViaOtherPhone = j['out_via_other_phone'] ?? false,
        photoUrl = j['photo_url'];
}

class DaySummary {
  final DateTime date;
  final int present;
  final int absent;
  final int stillIn;
  final List<DayRow> rows;

  DaySummary.fromJson(Map<String, dynamic> j)
      : date = DateTime.parse(j['date']),
        present = j['present'],
        absent = j['absent'],
        stillIn = j['still_in'],
        rows = (j['rows'] as List).map((r) => DayRow.fromJson(r)).toList();
}
