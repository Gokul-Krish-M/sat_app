import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/models.dart';

/// Holds login state. The device id is a random UUID created on first launch;
/// the server binds it to the employee who logs in on this phone.
class Session extends ChangeNotifier {
  Session() {
    api.onUnauthorized = () => logout(message: 'Session ended. Please log in again.');
  }

  final api = ApiClient();
  final _storage = const FlutterSecureStorage();

  AppUser? user;
  AppDevice? device;
  bool restoring = true;
  String? logoutMessage;

  bool get loggedIn => user != null;

  Future<String> _deviceId(String mobile) async {
    var id = await _storage.read(key: 'device_id');
    if (id == null) {
      id = const Uuid().v4();
      await _storage.write(key: 'device_id', value: id);
    }
    // Debug builds only: each mobile number gets its own device id, so one test
    // phone can log in as the admin and as an employee. Release builds bind the
    // phone to a single person as intended.
    if (kDebugMode) {
      final digits = mobile.replaceAll(RegExp(r'\D'), '');
      final last10 = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
      id = '$id-dev-$last10';
    }
    return id;
  }

  Future<void> restore() async {
    try {
      final token = await _storage.read(key: 'token');
      if (token != null) {
        api.token = token;
        final (u, d) = await api.me();
        user = u;
        device = d;
      }
    } on ApiException catch (e) {
      if (e.status == 401) await _storage.delete(key: 'token');
      // Offline: stay on login screen; user can retry.
      api.token = null;
    } finally {
      restoring = false;
      notifyListeners();
    }
  }

  Future<void> login(String mobile, String password) async {
    var model = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    if (model.length > 120) model = model.substring(0, 120);
    final (token, u, d) = await api.login(mobile.trim(), password, await _deviceId(mobile), model);
    api.token = token;
    await _storage.write(key: 'token', value: token);
    user = u;
    device = d;
    logoutMessage = null;
    notifyListeners();
  }

  /// Re-fetch user/device (e.g. admin just marked this phone as shared).
  Future<void> refresh() async {
    final (u, d) = await api.me();
    user = u;
    device = d;
    notifyListeners();
  }

  Future<void> logout({String? message}) async {
    await _storage.delete(key: 'token');
    api.token = null;
    user = null;
    device = null;
    logoutMessage = message;
    notifyListeners();
  }
}
