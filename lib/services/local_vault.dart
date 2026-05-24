import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/note.dart';
import 'vault_crypto.dart';

class LocalVaultSnapshot {
  const LocalVaultSnapshot({
    required this.notes,
    required this.lastPulledAt,
  });

  final List<Note> notes;
  final DateTime? lastPulledAt;
}

class LocalVault {
  LocalVault({
    FlutterSecureStorage? secureStorage,
    String profile = '',
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _profile = _cleanProfile(profile);

  static const _deviceIdKey = 'noterr_device_id';
  static const _saltKey = 'noterr_local_salt';
  static const _savedPassphraseKey = 'noterr_saved_passphrase';
  static const _fileName = 'noterr_vault.json';
  static const _uuid = Uuid();

  final FlutterSecureStorage _secureStorage;
  final String _profile;

  static String _cleanProfile(String profile) {
    final cleaned = profile.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return cleaned.isEmpty ? '' : cleaned;
  }

  String get _keySuffix => _profile.isEmpty ? '' : '_$_profile';

  Future<String> getOrCreateDeviceId() async {
    final existing = await _secureStorage.read(key: '$_deviceIdKey$_keySuffix');
    if (existing != null && existing.isNotEmpty) return existing;
    final next = _uuid.v4();
    await _secureStorage.write(key: '$_deviceIdKey$_keySuffix', value: next);
    return next;
  }

  Future<String> getOrCreateLocalSalt() async {
    final existing = await _secureStorage.read(key: '$_saltKey$_keySuffix');
    if (existing != null && existing.isNotEmpty) return existing;
    final next = VaultCrypto.randomSalt();
    await _secureStorage.write(key: '$_saltKey$_keySuffix', value: next);
    return next;
  }

  Future<String?> readSavedPassphrase() {
    return _secureStorage.read(key: '$_savedPassphraseKey$_keySuffix');
  }

  Future<void> savePassphrase(String passphrase) {
    return _secureStorage.write(
      key: '$_savedPassphraseKey$_keySuffix',
      value: passphrase,
    );
  }

  Future<void> clearSavedPassphrase() {
    return _secureStorage.delete(key: '$_savedPassphraseKey$_keySuffix');
  }

  Future<File> _vaultFile() async {
    final dir = await getApplicationSupportDirectory();
    final name = _profile.isEmpty ? _fileName : 'noterr_vault_$_profile.json';
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  Future<void> backUpVault({String suffix = 'backup'}) async {
    final file = await _vaultFile();
    if (!await file.exists()) return;
    final backup = File('${file.path}.$suffix');
    if (await backup.exists()) return;
    await file.copy(backup.path);
  }

  Future<LocalVaultSnapshot> load(SecretKey key) async {
    final file = await _vaultFile();
    if (!await file.exists()) {
      return const LocalVaultSnapshot(notes: [], lastPulledAt: null);
    }

    final encoded = await file.readAsString();
    if (encoded.trim().isEmpty) {
      return const LocalVaultSnapshot(notes: [], lastPulledAt: null);
    }

    final raw = jsonDecode(encoded) as Map<String, dynamic>;
    final payload = EncryptedPayload.fromJson(
      Map<String, dynamic>.from(raw['payload'] as Map),
    );
    final json = await VaultCrypto.decryptJson(payload, key);
    final notes = ((json['notes'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => Note.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    final lastPulledAt = json['lastPulledAt'] == null
        ? null
        : DateTime.tryParse(json['lastPulledAt'] as String)?.toUtc();

    return LocalVaultSnapshot(notes: notes, lastPulledAt: lastPulledAt);
  }

  Future<void> save(
    List<Note> notes,
    SecretKey key, {
    DateTime? lastPulledAt,
  }) async {
    final file = await _vaultFile();
    await file.parent.create(recursive: true);
    final payload = await VaultCrypto.encryptJson(
      {
        'notes': notes.map((note) => note.toJson()).toList(),
        'lastPulledAt': lastPulledAt?.toIso8601String(),
      },
      key,
    );
    await file.writeAsString(jsonEncode({'payload': payload.toJson()}));
  }
}
