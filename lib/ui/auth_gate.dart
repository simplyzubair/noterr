import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../controllers/noterr_controller.dart';
import '../services/local_vault.dart';
import '../services/remote_sync_service.dart';
import '../services/sticky_window_service.dart';
import '../services/widget_publisher.dart';
import 'unlock_screen.dart';
import 'workspace_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.hasCloud});

  final bool hasCloud;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final NoterrController _controller;

  @override
  void initState() {
    super.initState();
    final remote = widget.hasCloud
        ? SupabaseRemoteSyncService(Supabase.instance.client)
        : const NoopRemoteSyncService();
    _controller = NoterrController(
      localVault: LocalVault(),
      remote: remote,
      widgetPublisher: WidgetPublisher(),
    );
    StickyWindowService.instance.bindController(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (!_controller.isUnlocked) {
          return UnlockScreen(controller: _controller);
        }
        return WorkspaceScreen(controller: _controller);
      },
    );
  }
}
