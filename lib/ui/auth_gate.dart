import 'dart:async';

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
  const AuthGate({
    super.key,
    required this.hasCloud,
    this.dataProfile = '',
  });

  final bool hasCloud;
  final String dataProfile;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  late final NoterrController _controller;
  var _autoUnlockTried = false;
  var _autoUnlocking = false;

  @override
  void initState() {
    super.initState();
    final remote = widget.hasCloud
        ? SupabaseRemoteSyncService(Supabase.instance.client)
        : const NoopRemoteSyncService();
    _controller = NoterrController(
      localVault: LocalVault(profile: widget.dataProfile),
      remote: remote,
      widgetPublisher: WidgetPublisher(),
    );
    WidgetsBinding.instance.addObserver(this);
    StickyWindowService.instance.bindController(_controller);
    if (widget.hasCloud) {
      _autoUnlocking = true;
      unawaited(_tryAutoUnlock());
    }
  }

  Future<void> _tryAutoUnlock() async {
    if (_autoUnlockTried) return;
    _autoUnlockTried = true;
    try {
      await _controller.unlockSavedDevice();
    } catch (_) {
      // If the stored device key is invalid, the normal unlock screen appears.
    } finally {
      if (mounted) setState(() => _autoUnlocking = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _controller.isUnlocked) {
      unawaited(_controller.syncNow());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_autoUnlocking && !_controller.isUnlocked) {
          return const _AutoUnlockScreen();
        }
        if (!_controller.isUnlocked) {
          return UnlockScreen(controller: _controller);
        }
        return WorkspaceScreen(controller: _controller);
      },
    );
  }
}

class _AutoUnlockScreen extends StatelessWidget {
  const _AutoUnlockScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 18),
            Text('Opening Noterr'),
          ],
        ),
      ),
    );
  }
}
