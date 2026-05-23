import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<AuthResponse> signUp(String email, String password);
  Future<AuthResponse> signIn(String email, String password);
  Future<void> signOut();
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
  Future<AuthResponse> signIn(String email, String password) {
    throw UnsupportedError('Cloud sync is not configured.');
  }

  @override
  Future<AuthResponse> signUp(String email, String password) {
    throw UnsupportedError('Cloud sync is not configured.');
  }

  @override
  Future<void> signOut() async {}

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

class SupabaseRemoteSyncService implements RemoteSyncService {
  SupabaseRemoteSyncService(this._client);

  final SupabaseClient _client;

  @override
  bool get isAvailable => true;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<AuthResponse> signUp(String email, String password) {
    return _client.auth.signUp(email: email, password: password);
  }

  @override
  Future<AuthResponse> signIn(String email, String password) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<String> getOrCreateVaultSalt() async {
    final userId = currentUserId;
    if (userId == null) throw const AuthException('Not signed in.');

    final existing = await _client
        .from('noterr_profiles')
        .select('vault_salt')
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null && (existing['vault_salt'] as String).isNotEmpty) {
      return existing['vault_salt'] as String;
    }

    final salt = VaultCrypto.randomSalt();
    await _client.from('noterr_profiles').upsert({
      'user_id': userId,
      'vault_salt': salt,
    });
    return salt;
  }

  @override
  Future<List<Note>> pullNotes(SecretKey key) async {
    final userId = currentUserId;
    if (userId == null) return const [];

    final rows = await _client
        .from('noterr_notes')
        .select()
        .eq('owner_id', userId)
        .order('updated_at', ascending: false);

    final notes = <Note>[];
    for (final row in rows) {
      final envelope = RemoteNoteEnvelope.fromRow(Map<String, dynamic>.from(row));
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

  @override
  Future<void> pushNote(Note note, SecretKey key, String deviceId) async {
    final userId = currentUserId;
    if (userId == null) return;

    final payload = await VaultCrypto.encryptJson(note.toJson(), key);
    await _client.from('noterr_notes').upsert({
      'id': note.id,
      'owner_id': userId,
      'encrypted_payload': payload.cipherText,
      'nonce': payload.nonce,
      'mac': payload.mac,
      'payload_version': 1,
      'revision': note.revision,
      'device_id': deviceId,
      'deleted_at': note.deletedAt?.toIso8601String(),
    });
  }

  @override
  Stream<RemoteNoteEnvelope> watchNoteEnvelopes() {
    final userId = currentUserId;
    if (userId == null) return const Stream.empty();

    final controller = StreamController<RemoteNoteEnvelope>();
    final channel = _client.channel('public:noterr_notes:$userId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'noterr_notes',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'owner_id',
          value: userId,
        ),
        callback: (payload) {
          final row = payload.newRecord;
          if (row.isEmpty) return;
          controller.add(RemoteNoteEnvelope.fromRow(row));
        },
      )
      ..subscribe();

    controller.onCancel = () async {
      await _client.removeChannel(channel);
    };

    return controller.stream;
  }
}
