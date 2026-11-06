import 'package:flutter/material.dart';

import '../auth/session.dart';
import 'dashboard_screen.dart';
import 'devices_screen.dart';
import 'employees_screen.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key, required this.session});
  final Session session;

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(session: widget.session),
      EmployeesScreen(session: widget.session),
      DevicesScreen(session: widget.session),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today), label: 'Attendance'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Employees'),
          NavigationDestination(icon: Icon(Icons.phone_android), label: 'Phones'),
        ],
      ),
    );
  }
}
