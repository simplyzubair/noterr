import 'dart:convert';
import 'dart:io' show Platform;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_config.dart';
import 'app/noterr_app.dart';
import 'models/note.dart';
import 'ui/sticky_note_window.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final multiWindowController = await WindowController.fromCurrentEngine();
    final rawArguments = multiWindowController.arguments;
    final payload = rawArguments.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(rawArguments) as Map<String, dynamic>;
    if (payload['type'] == 'sticky') {
      final note = Note.fromJson(
        Map<String, dynamic>.from(payload['note'] as Map),
      );
      final bounds = note.bounds ?? StickyBounds.defaults();
      await windowManager.ensureInitialized();
      final options = WindowOptions(
        size: Size(bounds.width, bounds.height),
        minimumSize: const Size(220, 160),
        title: note.title.isEmpty ? 'Noterr sticky' : note.title,
        alwaysOnTop: note.isAlwaysOnTop,
        backgroundColor: Colors.transparent,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.setPosition(Offset(bounds.x, bounds.y));
        await windowManager.show();
        await windowManager.focus();
      });
      runApp(StickyNoteWindowApp(note: note));
      return;
    }
  }

  if (args.isNotEmpty && args.first == 'multi_window') {
    final payload = args.length > 2 && args[2].isNotEmpty
        ? jsonDecode(args[2]) as Map<String, dynamic>
        : <String, dynamic>{};
    if (payload['type'] == 'sticky') {
      final note = Note.fromJson(
        Map<String, dynamic>.from(payload['note'] as Map),
      );
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await windowManager.ensureInitialized();
      }
      runApp(
        StickyNoteWindowApp(
          note: note,
        ),
      );
      return;
    }
  }

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1180, 760),
      minimumSize: Size(860, 560),
      center: true,
      title: 'Noterr',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  if (AppConfig.hasSupabase) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }

  runApp(NoterrApp(hasCloud: AppConfig.hasSupabase));
}
