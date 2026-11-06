import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../config.dart';
import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

final _ymd = DateFormat('yyyy-MM-dd');

class ApiClient {
  ApiClient({this.onUnauthorized});

  String? token;

  /// Called on 401 (token expired, or admin reset this phone).
  void Function()? onUnauthorized;

  Map<String, String> get authHeaders =>
      token == null ? {} : {'Authorization': 'Bearer $token'};

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$apiUrl$path').replace(queryParameters: query);

  String imageUrl(String path) => '$apiUrl$path';

  Future<dynamic> _send(Future<http.Response> req) async {
    final http.Response res;
    try {
      res = await req.timeout(const Duration(seconds: 30));
    } catch (_) {
      throw ApiException(0, 'Cannot reach server. Check internet.');
    }
    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    if (res.statusCode == 401 && token != null) onUnauthorized?.call();
    if (res.statusCode >= 400) {
      String msg = 'Error ${res.statusCode}';
      try {
        final detail = jsonDecode(utf8.decode(res.bodyBytes))['detail'];
        msg = detail is String ? detail : msg;
      } catch (_) {}
      throw ApiException(res.statusCode, msg);
    }
    if (res.statusCode == 204 || res.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<dynamic> _get(String path, [Map<String, String>? q]) =>
      _send(http.get(_uri(path, q), headers: authHeaders));

  Future<dynamic> _json(String method, String path, Object body) {
    final req = http.Request(method, _uri(path))
      ..headers.addAll({...authHeaders, 'Content-Type': 'application/json'})
      ..body = jsonEncode(body);
    return _send(req.send().then(http.Response.fromStream));
  }

  Future<dynamic> _multipart(
      String path, Map<String, String> fields, Map<String, List<Uint8List>> files) {
    final req = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(authHeaders)
      ..fields.addAll(fields);
    files.forEach((name, list) {
      for (var i = 0; i < list.length; i++) {
        req.files.add(http.MultipartFile.fromBytes(name, list[i], filename: '$name$i.jpg'));
      }
    });
    return _send(req.send().then(http.Response.fromStream));
  }

  // ---------- auth ----------

  Future<(String, AppUser, AppDevice)> login(
      String mobile, String password, String deviceId, String deviceModel) async {
    final j = await _json('POST', '/auth/login', {
      'mobile': mobile,
      'password': password,
      'device_id': deviceId,
      'device_model': deviceModel,
    });
    return (j['token'] as String, AppUser.fromJson(j['user']), AppDevice.fromJson(j['device']));
  }

  Future<(AppUser, AppDevice)> me() async {
    final j = await _get('/auth/me');
    return (AppUser.fromJson(j['user']), AppDevice.fromJson(j['device']));
  }

  // ---------- attendance ----------

  Future<ClockResult> clock({
    required Uint8List image,
    required String liveness,
    int? forUserId,
    double? lat,
    double? lng,
    double? accuracyM,
  }) async {
    final fields = <String, String>{'liveness': liveness};
    if (forUserId != null) fields['for_user_id'] = '$forUserId';
    if (lat != null && lng != null) {
      fields['lat'] = '$lat';
      fields['lng'] = '$lng';
      if (accuracyM != null) fields['accuracy_m'] = '$accuracyM';
    }
    return ClockResult.fromJson(await _multipart('/attendance/clock', fields, {
      'image': [image]
    }));
  }

  Future<List<AttendanceEvent>> myToday() async =>
      (await _get('/attendance/me/today') as List).map((e) => AttendanceEvent.fromJson(e)).toList();

  Future<List<AppUser>> sharedStaff() async =>
      (await _get('/attendance/shared/staff') as List).map((e) => AppUser.fromJson(e)).toList();

  // ---------- admin ----------

  Future<List<AppUser>> employees() async =>
      (await _get('/admin/employees') as List).map((e) => AppUser.fromJson(e)).toList();

  /// The server assigns the employee number (EMP001, EMP002, ...).
  Future<AppUser> createEmployee(
      {required String name,
      required bool hasPhone,
      String? mobile,
      String? password,
      String role = 'employee'}) async {
    return AppUser.fromJson(await _json('POST', '/admin/employees', {
      'name': name,
      'mobile': ?mobile,
      'has_phone': hasPhone,
      'password': ?password,
      'role': role,
    }));
  }

  Future<AppUser> updateEmployee(int id,
      {String? name, String? mobile, bool? hasPhone, String? password, bool? active}) async {
    return AppUser.fromJson(await _json('PATCH', '/admin/employees/$id', {
      'name': ?name,
      'mobile': ?mobile,
      'has_phone': ?hasPhone,
      'password': ?password,
      'active': ?active,
    }));
  }

  Future<void> removeEmployee(int id) =>
      _send(http.delete(_uri('/admin/employees/$id'), headers: authHeaders));

  Future<AppUser> enroll(int id, List<Uint8List> photos) async =>
      AppUser.fromJson(await _multipart('/admin/employees/$id/enroll', {}, {'photos': photos}));

  Future<List<AppDevice>> devices() async =>
      (await _get('/admin/devices') as List).map((e) => AppDevice.fromJson(e)).toList();

  Future<AppDevice> setDeviceShared(int id, bool shared) async =>
      AppDevice.fromJson(await _json('PATCH', '/admin/devices/$id', {'is_shared': shared}));

  Future<void> resetDevice(int id) =>
      _send(http.delete(_uri('/admin/devices/$id'), headers: authHeaders));

  Future<DaySummary> daySummary(DateTime day) async =>
      DaySummary.fromJson(await _get('/admin/attendance', {'day': _ymd.format(day)}));

  Future<List<AttendanceEvent>> userEvents(int userId, DateTime day) async =>
      (await _get('/admin/attendance/$userId/events', {'day': _ymd.format(day)}) as List)
          .map((e) => AttendanceEvent.fromJson(e))
          .toList();

  /// Returns (filename, bytes) of the CSV report.
  Future<(String, Uint8List)> attendanceCsv(DateTime from, DateTime to) async {
    final res = await http
        .get(
            _uri('/admin/reports/attendance.csv',
                {'from': _ymd.format(from), 'to': _ymd.format(to)}),
            headers: authHeaders)
        .timeout(const Duration(seconds: 60));
    _decode(res.statusCode >= 400 ? res : http.Response('', 204));
    final name = RegExp(r'filename="([^"]+)"')
            .firstMatch(res.headers['content-disposition'] ?? '')
            ?.group(1) ??
        'attendance.csv';
    return (name, res.bodyBytes);
  }
}
