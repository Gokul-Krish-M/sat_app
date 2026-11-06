import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum Challenge { blink, smile }

class CaptureResult {
  final List<Uint8List> photos;
  final String liveness; // "blink" / "smile" / "enroll"
  CaptureResult(this.photos, this.liveness);
}

/// Front-camera face capture.
///
/// * Clock mode (default): a random blink-or-smile challenge, shown as a big
///   animated icon. The photo is taken automatically once the action is seen.
/// * Enroll mode: the admin taps the shutter [enrollCount] times.
class FaceCaptureScreen extends StatefulWidget {
  const FaceCaptureScreen({
    super.key,
    this.enrollCount = 0,
    this.personName,
    this.personPhoto,
  });

  final int enrollCount;
  final String? personName;
  final Widget? personPhoto;

  bool get enrollMode => enrollCount > 0;

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

enum _FaceState { none, many, adjust, ok }

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  static const _timeout = Duration(seconds: 25);
  static const _enrollHints = ['Look straight', 'Turn head slightly left', 'Turn head slightly right',
    'Look straight', 'Look straight'];

  CameraController? _cam;
  late final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, // eye-open & smile probabilities
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.2,
    ),
  );

  String? _error;
  bool _busy = false;
  bool _capturing = false;
  bool _timedOut = false;
  Timer? _timeoutTimer;
  Timer? _animTimer;
  bool _animPhase = false;

  _FaceState _face = _FaceState.none;
  late Challenge _challenge;
  // Blink: open -> closed -> open. Smile: neutral -> smile.
  bool _sawOpen = false, _sawClosed = false, _sawNeutral = false;

  final List<Uint8List> _enrollPhotos = [];

  @override
  void initState() {
    super.initState();
    _newChallenge();
    _animTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (mounted) setState(() => _animPhase = !_animPhase);
    });
    _initCamera();
  }

  void _newChallenge() {
    _challenge = Challenge.values[Random().nextInt(Challenge.values.length)];
    _sawOpen = _sawClosed = _sawNeutral = false;
    _timedOut = false;
    _timeoutTimer?.cancel();
    if (!widget.enrollMode) {
      _timeoutTimer = Timer(_timeout, () {
        if (mounted && !_capturing) setState(() => _timedOut = true);
      });
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first);
      final cam = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await cam.initialize();
      if (!mounted) {
        await cam.dispose();
        return;
      }
      setState(() => _cam = cam);
      await cam.startImageStream(_onFrame);
    } on CameraException catch (e) {
      setState(() => _error = e.code == 'CameraAccessDenied'
          ? 'Camera permission is needed. Enable it in phone Settings.'
          : 'Camera error: ${e.description}');
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _animTimer?.cancel();
    _cam?.dispose();
    _detector.close();
    super.dispose();
  }

  // ---------- frame analysis ----------

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _capturing || _timedOut) return;
    _busy = true;
    try {
      final rotation = _rotation();
      final input = _toInputImage(image, rotation);
      if (input == null) return;
      final faces = await _detector.processImage(input);
      final uprightWidth = (rotation == InputImageRotation.rotation90deg ||
              rotation == InputImageRotation.rotation270deg)
          ? image.height
          : image.width;
      _evaluate(faces, uprightWidth.toDouble());
    } catch (_) {
      // Skip a bad frame.
    } finally {
      _busy = false;
    }
  }

  InputImageRotation _rotation() {
    // The app is locked to portrait, so only the sensor orientation matters.
    return InputImageRotationValue.fromRawValue(_cam!.description.sensorOrientation) ??
        InputImageRotation.rotation0deg;
  }

  InputImage? _toInputImage(CameraImage image, InputImageRotation rotation) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null || image.planes.length != 1) return null;
    if (Platform.isAndroid && format != InputImageFormat.nv21) return null;
    if (Platform.isIOS && format != InputImageFormat.bgra8888) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  void _evaluate(List<Face> faces, double frameWidth) {
    _FaceState state;
    Face? face;
    if (faces.isEmpty) {
      state = _FaceState.none;
    } else if (faces.length > 1) {
      state = _FaceState.many;
    } else {
      face = faces.first;
      final bigEnough = face.boundingBox.width / frameWidth > 0.28;
      final maxYaw = widget.enrollMode ? 30 : 15;
      final straight = (face.headEulerAngleY ?? 0).abs() < maxYaw &&
          (face.headEulerAngleZ ?? 0).abs() < 15;
      state = bigEnough && straight ? _FaceState.ok : _FaceState.adjust;
    }
    if (state != _face && mounted) setState(() => _face = state);
    if (state != _FaceState.ok || widget.enrollMode || face == null) return;

    switch (_challenge) {
      case Challenge.blink:
        final l = face.leftEyeOpenProbability, r = face.rightEyeOpenProbability;
        if (l == null || r == null) return;
        final open = l > 0.7 && r > 0.7;
        final closed = l < 0.25 && r < 0.25;
        if (!_sawOpen) {
          if (open) _sawOpen = true;
        } else if (!_sawClosed) {
          if (closed) setState(() => _sawClosed = true);
        } else if (open) {
          _capture(); // eyes re-opened: take the photo with eyes open
        }
      case Challenge.smile:
        final s = face.smilingProbability;
        if (s == null) return;
        if (!_sawNeutral) {
          if (s < 0.3) _sawNeutral = true;
        } else if (s > 0.8) {
          _capture();
        }
    }
  }

  // ---------- capture ----------

  Future<void> _capture() async {
    final cam = _cam;
    if (cam == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      await cam.stopImageStream();
      final file = await cam.takePicture();
      final bytes = await file.readAsBytes();
      unawaited(File(file.path).delete().catchError((_) => File(file.path)));
      HapticFeedback.heavyImpact();
      if (!mounted) return;

      if (!widget.enrollMode) {
        Navigator.of(context).pop(CaptureResult([bytes], _challenge.name));
        return;
      }
      _enrollPhotos.add(bytes);
      if (_enrollPhotos.length >= widget.enrollCount) {
        Navigator.of(context).pop(CaptureResult(_enrollPhotos, 'enroll'));
        return;
      }
      await cam.startImageStream(_onFrame);
      setState(() => _capturing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      try {
        await cam.startImageStream(_onFrame);
      } catch (_) {}
    }
  }

  void _retry() {
    setState(_newChallenge);
  }

  // ---------- UI ----------

  Color get _ringColor => switch (_face) {
        _FaceState.ok => Colors.greenAccent,
        _FaceState.adjust => Colors.amber,
        _FaceState.many => Colors.redAccent,
        _FaceState.none => Colors.white54,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _error != null
            ? _ErrorView(message: _error!)
            : _cam == null
                ? const Center(child: CircularProgressIndicator())
                : Stack(fit: StackFit.expand, children: [
                    _preview(),
                    _ovalOverlay(),
                    Positioned(top: 8, left: 8, child: _closeButton()),
                    Positioned(top: 16, left: 0, right: 0, child: _topPanel()),
                    Positioned(bottom: 24, left: 0, right: 0, child: _bottomPanel()),
                  ]),
      ),
    );
  }

  Widget _preview() {
    final cam = _cam!;
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * cam.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return ClipRect(
      child: Transform.scale(scale: scale, child: Center(child: CameraPreview(cam))),
    );
  }

  Widget _ovalOverlay() {
    return IgnorePointer(
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 260,
          height: 340,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.elliptical(130, 170)),
            border: Border.all(color: _ringColor, width: 6),
          ),
        ),
      ),
    );
  }

  Widget _closeButton() => IconButton(
        iconSize: 36,
        color: Colors.white,
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).pop(),
      );

  Widget _topPanel() {
    final person = widget.personName == null
        ? const SizedBox.shrink()
        : Column(children: [
            if (widget.personPhoto != null)
              SizedBox(width: 64, height: 64, child: ClipOval(child: widget.personPhoto)),
            Text(widget.personName!,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          ]);
    if (widget.enrollMode) {
      final n = _enrollPhotos.length;
      return Column(children: [
        person,
        const SizedBox(height: 8),
        _pill('Photo ${n + 1} of ${widget.enrollCount}: ${_enrollHints[n % _enrollHints.length]}'),
      ]);
    }
    return Column(children: [person, const SizedBox(height: 8), _challengeIcon()]);
  }

  Widget _challengeIcon() {
    final IconData icon;
    final String label;
    switch (_challenge) {
      case Challenge.blink:
        icon = _animPhase ? Icons.visibility_off : Icons.visibility;
        label = 'Blink';
      case Challenge.smile:
        icon = _animPhase ? Icons.sentiment_very_satisfied : Icons.sentiment_neutral;
        label = 'Smile';
    }
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Icon(icon, key: ValueKey(icon), size: 96, color: Colors.white),
        ),
      ),
      const SizedBox(height: 4),
      // Optional small label; the icon alone is the instruction.
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 16)),
    ]);
  }

  Widget _bottomPanel() {
    if (_capturing) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_timedOut) {
      return Center(
        child: IconButton.filled(
          iconSize: 64,
          icon: const Icon(Icons.refresh),
          onPressed: _retry,
        ),
      );
    }
    if (widget.enrollMode) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        if (_enrollPhotos.isNotEmpty)
          SizedBox(
            height: 56,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final p in _enrollPhotos)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(p, width: 42, height: 56, fit: BoxFit.cover)),
                ),
            ]),
          ),
        const SizedBox(height: 12),
        Center(
          child: IconButton.filled(
            iconSize: 56,
            style: IconButton.styleFrom(
                backgroundColor: _face == _FaceState.ok ? Colors.green : Colors.grey),
            icon: const Icon(Icons.camera_alt),
            onPressed: _face == _FaceState.ok ? _capture : null,
          ),
        ),
      ]);
    }
    // Wordless face-position hint.
    final hint = switch (_face) {
      _FaceState.none => Icons.face_retouching_off,
      _FaceState.many => Icons.group_off,
      _FaceState.adjust => Icons.center_focus_strong,
      _FaceState.ok => _challenge == Challenge.blink && _sawClosed ? Icons.check : null,
    };
    return hint == null
        ? const SizedBox.shrink()
        : Center(child: Icon(hint, size: 56, color: _ringColor));
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(24)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 16)),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography, size: 72, color: Colors.white),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 24),
            IconButton.filled(
                iconSize: 40,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop()),
          ]),
        ),
      );
}
