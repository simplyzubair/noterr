import 'package:flutter/material.dart';

import '../controllers/noterr_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});

  final NoterrController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool create}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (create) {
        await widget.controller.signUp(_email.text.trim(), _password.text);
      } else {
        await widget.controller.signIn(_email.text.trim(), _password.text);
      }
    } catch (error) {
      setState(() => _error = _friendlyAuthError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyAuthError(Object error) {
    final message = error.toString();
    if (message.contains('over_email_send_rate_limit')) {
      final seconds = RegExp(r'after (\d+) seconds').firstMatch(message)?.group(1);
      return seconds == null
          ? 'Please wait a little before requesting another sign-up email.'
          : 'Please wait $seconds seconds before requesting another sign-up email.';
    }
    if (message.contains('Email not confirmed')) {
      return 'Please confirm your email first, or disable email confirmation in Supabase while testing.';
    }
    if (message.contains('Invalid login credentials')) {
      return 'Email or password is incorrect.';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Noterr',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to sync encrypted sticky notes.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _submit(create: false),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: const Text('Sign in'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _submit(create: true),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Create account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
