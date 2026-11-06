/// Backend URL. Override at build time:
///   flutter run --dart-define=API_URL=http://192.168.1.10:8000
/// (Android emulator reaches the host machine at 10.0.2.2.)
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8000');
