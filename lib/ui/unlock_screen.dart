import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/noterr_controller.dart';

// ── PIN entry mode ────────────────────────────────────────────────────────────
enum _PinMode { loading, create, confirm, enter }

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.controller});

  final NoterrController controller;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen>
    with SingleTickerProviderStateMixin {
  static const _pinLength = 6;

  _PinMode _mode = _PinMode.loading;
  String _firstPin = '';   // stores the first entry during confirm step

  final List<TextEditingController> _controllers =
      List.generate(_pinLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(_pinLength, (_) => FocusNode());

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut),
    );
    _detectMode();
  }

  Future<void> _detectMode() async {
    final firstTime = await widget.controller.isFirstTimeSetup();
    if (!mounted) return;
    setState(() => _mode = firstTime ? _PinMode.create : _PinMode.enter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _shakeController.dispose();
    super.dispose();
  }

  String get _pin => _controllers.map((c) => c.text).join();

  void _clearBoxes() {
    for (final c in _controllers) {
      c.clear();
    }
    if (mounted) _focusNodes[0].requestFocus();
    setState(() {});
  }

  void _shakeAndError(String msg) {
    setState(() => _error = msg);
    _shakeController.forward(from: 0);
    _clearBoxes();
  }

  // Called when all 6 digits have been entered (last box triggers this).
  Future<void> _onPinComplete() async {
    final pin = _pin;

    if (_mode == _PinMode.create) {
      // Step 1 of 2: store and ask for confirm.
      setState(() {
        _firstPin = pin;
        _mode = _PinMode.confirm;
        _error = null;
      });
      _clearBoxes();
      return;
    }

    if (_mode == _PinMode.confirm) {
      // Step 2 of 2: verify match then unlock.
      if (pin != _firstPin) {
        _shakeAndError('PINs do not match. Please try again.');
        setState(() {
          _firstPin = '';
          _mode = _PinMode.create;
        });
        return;
      }
      await _doUnlock(pin);
      return;
    }

    // Normal enter mode.
    await _doUnlock(pin);
  }

  Future<void> _doUnlock(String pin) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.unlock(pin);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        _shakeAndError(_friendlyError(error));
        if (_mode == _PinMode.confirm) {
          // Reset to create if cloud rejected the pin.
          setState(() {
            _firstPin = '';
            _mode = _PinMode.create;
          });
        }
      }
    }
  }

  String _friendlyError(Object error) {
    final msg = error.toString();
    if (msg.contains('Enter a sync passkey')) return 'Enter all 6 digits.';
    if (msg.toLowerCase().contains('unknown sync profile')) {
      return 'Sync profile not found. Try again while online.';
    }
    if (msg.toLowerCase().contains('socket') ||
        msg.toLowerCase().contains('failed host lookup')) {
      return 'Cannot reach sync service. Check internet and retry.';
    }
    if (msg.toLowerCase().contains('mac') ||
        msg.toLowerCase().contains('decrypt') ||
        msg.toLowerCase().contains('incorrect')) {
      return 'Wrong PIN. Try again.';
    }
    return msg;
  }

  void _onDigitChanged(int index, String value) {
    if (value.length == 1) {
      if (index < _pinLength - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        _onPinComplete();
      }
    }
    setState(() {});
  }

  void _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
      setState(() {});
    }
  }

  // ── UI helpers ──────────────────────────────────────────────────────────────

  String get _titleText {
    switch (_mode) {
      case _PinMode.loading:
        return 'Opening Noterr…';
      case _PinMode.create:
        return 'Create your sync PIN';
      case _PinMode.confirm:
        return 'Confirm your PIN';
      case _PinMode.enter:
        return widget.controller.hasCloud ? 'Enter sync PIN' : 'Unlock notes';
    }
  }

  String get _subtitleText {
    switch (_mode) {
      case _PinMode.loading:
        return '';
      case _PinMode.create:
        return 'Choose a 6-digit PIN.\nUse the same PIN on every device — it encrypts all your notes.';
      case _PinMode.confirm:
        return 'Enter the same 6-digit PIN again to confirm.';
      case _PinMode.enter:
        return widget.controller.hasCloud
            ? 'Use the same 6-digit PIN on every device.\nIt encrypts and syncs your notes.'
            : 'Enter your 6-digit PIN to unlock notes.';
    }
  }

  IconData get _headerIcon {
    switch (_mode) {
      case _PinMode.create:
        return Icons.lock_reset_rounded;
      case _PinMode.confirm:
        return Icons.check_circle_outline_rounded;
      default:
        return Icons.sticky_note_2_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filled = _pin.length;

    if (_mode == _PinMode.loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: scheme.primary),
              const SizedBox(height: 18),
              const Text('Opening Noterr…'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon badge
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    key: ValueKey(_mode),
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _mode == _PinMode.create || _mode == _PinMode.confirm
                          ? scheme.tertiaryContainer
                          : scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      _headerIcon,
                      size: 38,
                      color: _mode == _PinMode.create || _mode == _PinMode.confirm
                          ? scheme.onTertiaryContainer
                          : scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Step indicator for create flow
                if (_mode == _PinMode.create || _mode == _PinMode.confirm) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepDot(active: true, done: _mode == _PinMode.confirm),
                      const SizedBox(width: 8),
                      _StepDot(active: _mode == _PinMode.confirm, done: false),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Title
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    _titleText,
                    key: ValueKey(_titleText),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    _subtitleText,
                    key: ValueKey(_subtitleText),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                  ),
                ),
                const SizedBox(height: 36),

                // 6-digit boxy PIN input with shake on error
                AnimatedBuilder(
                  animation: _shakeAnimation,
                  builder: (context, child) {
                    final offset = _error != null
                        ? 10 *
                            _shakeAnimation.value *
                            ((_shakeController.value * 10).round() % 2 == 0
                                ? 1
                                : -1)
                        : 0.0;
                    return Transform.translate(
                      offset: Offset(offset, 0),
                      child: child,
                    );
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pinLength, (i) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: _DigitBox(
                          controller: _controllers[i],
                          focusNode: _focusNodes[i],
                          hasError: _error != null,
                          isSetup: _mode == _PinMode.create ||
                              _mode == _PinMode.confirm,
                          onChanged: (v) => _onDigitChanged(i, v),
                          onKeyEvent: (e) => _onKeyEvent(i, e),
                        ),
                      );
                    }),
                  ),
                ),

                // Error message
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline,
                                  size: 16, color: scheme.error),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                      color: scheme.error, fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 28),

                // Unlock / Set PIN button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: (_busy || filled < _pinLength)
                        ? null
                        : _onPinComplete,
                    style: _mode == _PinMode.create || _mode == _PinMode.confirm
                        ? FilledButton.styleFrom(
                            backgroundColor: scheme.tertiary,
                            foregroundColor: scheme.onTertiary,
                          )
                        : null,
                    icon: _busy
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.onPrimary,
                            ),
                          )
                        : Icon(
                            _mode == _PinMode.create
                                ? Icons.arrow_forward_rounded
                                : _mode == _PinMode.confirm
                                    ? Icons.check_rounded
                                    : Icons.lock_open_rounded,
                            size: 20,
                          ),
                    label: Text(
                      _busy
                          ? (_mode == _PinMode.confirm
                              ? 'Setting PIN…'
                              : 'Unlocking…')
                          : (_mode == _PinMode.create
                              ? 'Next'
                              : _mode == _PinMode.confirm
                                  ? 'Confirm PIN'
                                  : 'Unlock'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Clear / back link
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() {
                            _error = null;
                            if (_mode == _PinMode.confirm) {
                              _firstPin = '';
                              _mode = _PinMode.create;
                            }
                          });
                          _clearBoxes();
                        },
                  child: Text(
                    _mode == _PinMode.confirm ? '← Back' : 'Clear',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step dot indicator for create/confirm flow
// ─────────────────────────────────────────────────────────────────────────────

class _StepDot extends StatelessWidget {
  const _StepDot({required this.active, required this.done});
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: done ? 24 : (active ? 24 : 8),
      height: 8,
      decoration: BoxDecoration(
        color: active || done
            ? scheme.tertiary
            : scheme.outlineVariant,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single digit box
// ─────────────────────────────────────────────────────────────────────────────

class _DigitBox extends StatefulWidget {
  const _DigitBox({
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.isSetup,
    required this.onChanged,
    required this.onKeyEvent,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasError;
  final bool isSetup;   // true during create/confirm — uses tertiary color
  final ValueChanged<String> onChanged;
  final ValueChanged<KeyEvent> onKeyEvent;

  @override
  State<_DigitBox> createState() => _DigitBoxState();
}

class _DigitBoxState extends State<_DigitBox> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final focused = widget.focusNode.hasFocus;
    final filled = widget.controller.text.isNotEmpty;
    final accentColor =
        widget.isSetup ? scheme.tertiary : scheme.primary;
    final accentContainerColor =
        widget.isSetup ? scheme.tertiaryContainer : scheme.primaryContainer;

    Color borderColor;
    double borderWidth;
    if (widget.hasError) {
      borderColor = scheme.error;
      borderWidth = 2.0;
    } else if (focused) {
      borderColor = accentColor;
      borderWidth = 2.0;
    } else if (filled) {
      borderColor = accentColor.withValues(alpha: 0.5);
      borderWidth = 1.5;
    } else {
      borderColor = scheme.outlineVariant;
      borderWidth = 1.5;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 50,
      height: 58,
      decoration: BoxDecoration(
        color: focused
            ? accentContainerColor.withValues(alpha: 0.35)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ]
            : null,
      ),
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: widget.onKeyEvent,
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          obscureText: true,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
            letterSpacing: 0,
          ),
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}

