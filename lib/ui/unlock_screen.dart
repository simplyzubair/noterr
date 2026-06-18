import 'package:flutter/material.dart';

import '../controllers/noterr_controller.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.controller});

  final NoterrController controller;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _passphrase = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.unlock(_passphrase.text);
    } catch (error) {
      setState(() => _error = _friendlyUnlockError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyUnlockError(Object error) {
    final message = error.toString();
    if (message.contains('Enter a sync passkey')) {
      return 'Enter a sync passkey.';
    }
    if (message.toLowerCase().contains('unknown sync profile')) {
      return 'Sync profile was not found. Try unlocking once while online.';
    }
    if (message.toLowerCase().contains('socket') ||
        message.toLowerCase().contains('failed host lookup')) {
      return 'Cannot reach sync service. Check internet and try again.';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.sticky_note_2_outlined, size: 56, color: scheme.primary),
                const SizedBox(height: 20),
                Text(
                  widget.controller.hasCloud ? 'Enter sync passkey' : 'Unlock notes',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.controller.hasCloud
                      ? 'Use one private passkey on every device. It encrypts and syncs your notes.'
                      : 'Use the same sync passphrase on every device.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _passphrase,
                  obscureText: true,
                  onSubmitted: (_) => _unlock(),
                  decoration: const InputDecoration(
                    labelText: 'Sync passphrase',
                    prefixIcon: Icon(Icons.key),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _unlock,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
