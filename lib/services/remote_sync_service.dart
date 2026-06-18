import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import '../models/note.dart';
import 'vault_crypto.dart';

class RemoteNoteEnvelope {
  const RemoteNoteEnvelope({
    required this.id,
    required this.encryptedPayload,
    required this.nonce,
    required this.mac,
    required this.revision,
    required this.deviceId,
    required this.updatedAt,
    this.deletedAt,
  });

  factory RemoteNoteEnvelope.fromRow(Map<String, dynamic> row) {
    return RemoteNoteEnvelope(
      id: row['id'] as String,
      encryptedPayload: row['encrypted_payload'] as String,
      nonce: row['nonce'] as String,
      mac: row['mac'] as String,
      revision: (row['revision'] as num?)?.toInt() ?? 1,
      deviceId: row['device_id'] as String? ?? '',
      updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
      deletedAt: row['deleted_at'] == null
          ? null
          : DateTime.tryParse(row['deleted_at'] as String)?.toUtc(),
    );
  }

  final String id;
  final String encryptedPayload;
  final String nonce;
  final String mac;
  final int revision;
  final String deviceId;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

abstract class RemoteSyncService {
  bool get isAvailable;
  String? get currentUserId;

  Future<void> openSyncProfile(String passphrase, {required String vaultSalt});
  Future<void> closeSyncProfile();
  Future<String> getOrCreateVaultSalt();
  Future<List<Note>> pullNotes(SecretKey key);
  Future<void> pushNote(Note note, SecretKey key, String deviceId);
  Stream<RemoteNoteEnvelope> watchNoteEnvelopes();
}

class NoopRemoteSyncService implements RemoteSyncService {
  const NoopRemoteSyncService();

  @override
  bool get isAvailable => false;

  @override
  String? get currentUserId => null;

  @override
  Future<void> openSyncProfile(
    String passphrase, {
    required String vaultSalt,
  }) async {}

  @override
  Future<void> closeSyncProfile() async {}

  @override
  Future<String> getOrCreateVaultSalt() {
    throw UnsupportedError('Cloud sync is not configured.');
  }

  @override
  Future<List<Note>> pullNotes(SecretKey key) async => const [];

  @override
  Future<void> pushNote(Note note, SecretKey key, String deviceId) async {}

  @override
  Stream<RemoteNoteEnvelope> watchNoteEnvelopes() => const Stream.empty();
}

class CloudflareRemoteSyncService implements RemoteSyncService {
  CloudflareRemoteSyncService(String syncUrl)
      : _baseUri = Uri.parse(syncUrl.replaceFirst(RegExp(r'/+$'), ''));

  final Uri _baseUri;
  String? _syncId;
  String? _vaultSalt;

  @override
  bool get isAvailable => true;

  @override
  String? get currentUserId => _syncId;

  @override
  Future<void> openSyncProfile(
    String passphrase, {
    required String vaultSalt,
  }) async {
    final credentials = await VaultCrypto.syncCredentials(passphrase);
    final syncId = _syncIdFromEmail(credentials.email);
    final response = await _post('/profile', {
      'syncId': syncId,
      'vaultSalt': vaultSalt,
    });
    _syncId = syncId;
    _vaultSalt = response['vaultSalt'] as String;
  }

  @override
  Future<void> closeSyncProfile() async {
    _syncId = null;
    _vaultSalt = null;
  }

  @override
  Future<String> getOrCreateVaultSalt() async {
    final salt = _vaultSalt;
    if (salt == null || salt.isEmpty) {
      throw StateError('Cloud sync profile is not open.');
    }
    return salt;
  }

  @override
  Future<List<Note>> pullNotes(SecretKey key) async {
    final syncId = _requireSyncId();
    final response = await _post('/pull', {'syncId': syncId});
    return _decodeNotes(response, key);
  }

  @override
  Future<void> pushNote(Note note, SecretKey key, String deviceId) async {
    final syncId = _requireSyncId();
    final payload = await VaultCrypto.encryptJson(note.toJson(), key);
    await _post('/push', {
      'syncId': syncId,
      'note': {
        'id': note.id,
        'encrypted_payload': payload.cipherText,
        'nonce': payload.nonce,
        'mac': payload.mac,
        'payload_version': 1,
        'revision': note.revision,
        'device_id': deviceId,
        'deleted_at': note.deletedAt?.toIso8601String(),
      },
    });
  }

  @override
  Stream<RemoteNoteEnvelope> watchNoteEnvelopes() => const Stream.empty();

  Future<List<Note>> _decodeNotes(
    Map<String, dynamic> response,
    SecretKey key,
  ) async {
    final rows = ((response['notes'] as List?) ?? const [])
        .whereType<Map>()
        .map((row) => RemoteNoteEnvelope.fromRow(
              Map<String, dynamic>.from(row),
            ));
    final notes = <Note>[];
    for (final envelope in rows) {
      final payload = EncryptedPayload(
        cipherText: envelope.encryptedPayload,
        nonce: envelope.nonce,
        mac: envelope.mac,
      );
      final json = await VaultCrypto.decryptJson(payload, key);
      notes.add(Note.fromJson(json));
    }
    return notes;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http
        .post(
          _baseUri.resolve(path),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    final decoded = response.body.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(decoded['error'] ?? 'Cloud sync failed.');
    }
    return decoded;
  }

  String _requireSyncId() {
    final syncId = _syncId;
    if (syncId == null || syncId.isEmpty) {
      throw StateError('Cloud sync profile is not open.');
    }
    return syncId;
  }

  String _syncIdFromEmail(String email) {
    final match = RegExp(r'^vault-([a-f0-9]{40})@noterr\.local$')
        .firstMatch(email);
    if (match == null) throw StateError('Invalid sync passphrase.');
    return match.group(1)!;
  }
}
