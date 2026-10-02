import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class StartupService {
  const StartupService();

  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _valueName = 'Noterr';
  static const _settingsFileName = 'noterr_settings.json';
  static const _startOnLoginKey = 'startOnLogin';

  bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<bool> ensureDefaultEnabled() async {
    if (!isSupported) return false;
    final preference = await _readPreference();
    if (preference != null) {
      await _apply(preference);
      return preference;
    }
    await setEnabled(true);
    return true;
  }

  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    final preference = await _readPreference();
    if (preference != null) return preference;
    return _isApplied();
  }

  Future<void> setEnabled(bool enabled) async {
    if (!isSupported) return;
    await _writePreference(enabled);
    await _apply(enabled);
  }

  Future<bool?> _readPreference() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return json[_startOnLoginKey] as bool?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writePreference(bool enabled) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({_startOnLoginKey: enabled}));
  }

  Future<File> _settingsFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_settingsFileName');
  }

  Future<bool> _isApplied() async {
    if (!Platform.isWindows) return false;
    final result = await Process.run(
      'reg',
      ['query', _runKey, '/v', _valueName],
      runInShell: true,
    );
    return result.exitCode == 0 &&
        result.stdout.toString().contains(Platform.resolvedExecutable);
  }

  Future<void> _apply(bool enabled) async {
    if (!Platform.isWindows) return;
    if (enabled) {
      await Process.run(
        'reg',
        [
          'add',
          _runKey,
          '/v',
          _valueName,
          '/t',
          'REG_SZ',
          '/d',
          '"${Platform.resolvedExecutable}" --start-hidden',
          '/f',
        ],
        runInShell: true,
      );
    } else {
      await Process.run(
        'reg',
        ['delete', _runKey, '/v', _valueName, '/f'],
        runInShell: true,
      );
    }
  }
}
