import 'package:flutter/material.dart';

import '../ui/auth_gate.dart';
import 'theme.dart';

class NoterrApp extends StatelessWidget {
  const NoterrApp({super.key, required this.hasCloud});

  final bool hasCloud;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Noterr',
      debugShowCheckedModeBanner: false,
      theme: buildNoterrTheme(Brightness.light),
      darkTheme: buildNoterrTheme(Brightness.dark),
      home: AuthGate(hasCloud: hasCloud),
    );
  }
}
