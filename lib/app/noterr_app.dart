import 'package:flutter/material.dart';

import '../ui/auth_gate.dart';
import 'theme.dart';

/// Lets services outside the widget tree (evening reminders) open screens.
final noterrNavigatorKey = GlobalKey<NavigatorState>();

class NoterrApp extends StatelessWidget {
  const NoterrApp({
    super.key,
    required this.hasCloud,
    this.dataProfile = '',
    this.startHidden = false,
  });

  final bool hasCloud;
  final String dataProfile;
  final bool startHidden;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: noterrNavigatorKey,
      title: 'Noterr',
      debugShowCheckedModeBanner: false,
      theme: buildNoterrTheme(Brightness.light),
      darkTheme: buildNoterrTheme(Brightness.dark),
      home: AuthGate(
        hasCloud: hasCloud,
        dataProfile: dataProfile,
        startHidden: startHidden,
      ),
    );
  }
}
