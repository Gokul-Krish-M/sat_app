import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin/admin_home.dart';
import 'auth/login_screen.dart';
import 'auth/session.dart';
import 'clock/employee_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Face detection assumes portrait (see FaceCaptureScreen._rotation).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final session = Session();
  session.restore();
  runApp(AttendanceApp(session: session));
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key, required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo, brightness: Brightness.dark, useMaterial3: true),
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (session.restoring) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (!session.loggedIn) return LoginScreen(key: UniqueKey(), session: session);
          return session.user!.isAdmin
              ? AdminHome(session: session)
              : EmployeeHome(session: session);
        },
      ),
    );
  }
}
