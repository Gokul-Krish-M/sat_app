import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../widgets/auth_image.dart';
import 'face_capture_screen.dart';

/// Ask for location permission once (from the home screen), so the clock flow
/// never shows a permission dialog on top of the camera.
Future<void> ensureLocationPermission() async {
  try {
    if (await Geolocator.checkPermission() == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
  } catch (_) {}
}

/// Best effort; collected now for phase-2 geo-fencing, never blocks clock-in.
Future<Position?> _tryPosition() async {
  try {
    final p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
    );
  } catch (_) {
    return null;
  }
}

/// Full clock-in/out: camera + liveness -> upload -> big result screen.
/// [forUser] is set when clocking in a no-phone employee on a shared phone.
Future<void> runClockFlow(BuildContext context, ApiClient api, {AppUser? forUser}) async {
  final position = _tryPosition();
  final capture = await Navigator.of(context).push<CaptureResult>(MaterialPageRoute(
    builder: (_) => FaceCaptureScreen(
      personName: forUser?.name,
      personPhoto: forUser == null ? null : AuthImage(api, forUser.photoPath),
    ),
  ));
  if (capture == null || !context.mounted) return;

  final future = () async {
    final pos = await position.timeout(const Duration(seconds: 3), onTimeout: () => null);
    return api.clock(
      image: capture.photos.first,
      liveness: capture.liveness,
      forUserId: forUser?.id,
      lat: pos?.latitude,
      lng: pos?.longitude,
      accuracyM: pos?.accuracy,
    );
  }();

  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ClockResultScreen(result: future),
  ));
}

class ClockResultScreen extends StatefulWidget {
  const ClockResultScreen({super.key, required this.result});
  final Future<ClockResult> result;

  @override
  State<ClockResultScreen> createState() => _ClockResultScreenState();
}

class _ClockResultScreenState extends State<ClockResultScreen> {
  ClockResult? _result;
  String? _error;
  Timer? _close;

  @override
  void initState() {
    super.initState();
    widget.result.then((r) {
      if (!mounted) return;
      setState(() => _result = r);
      r.accepted ? HapticFeedback.mediumImpact() : HapticFeedback.vibrate();
      _autoClose();
    }).catchError((Object e) {
      if (!mounted) return;
      setState(() => _error = e is ApiException ? e.message : 'Something went wrong');
      HapticFeedback.vibrate();
      _autoClose();
    });
  }

  void _autoClose() {
    _close = Timer(const Duration(seconds: 4), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _close?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final ok = r?.accepted ?? false;
    final loading = r == null && _error == null;
    final bg = loading ? Colors.blueGrey : (ok ? Colors.green.shade600 : Colors.red.shade600);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: InkWell(
          onTap: loading ? null : () => Navigator.of(context).pop(),
          child: Center(
            child: loading
                ? const CircularProgressIndicator(color: Colors.white)
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(ok ? Icons.check_circle : Icons.cancel, size: 160, color: Colors.white),
                    const SizedBox(height: 16),
                    if (ok) ...[
                      Icon(r!.type == 'IN' ? Icons.login : Icons.logout,
                          size: 64, color: Colors.white),
                      Text(r.type!,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
                      Text(DateFormat.jm().format(r.ts!),
                          style: const TextStyle(color: Colors.white, fontSize: 28)),
                    ],
                    if (r != null)
                      Text(r.employeeName,
                          style: const TextStyle(color: Colors.white, fontSize: 22)),
                    if (!ok)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error ?? r!.message,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 18)),
                      ),
                  ]),
          ),
        ),
      ),
    );
  }
}
