// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:noterr/models/note.dart';
import 'package:noterr/services/vault_crypto.dart';

class AuthSession {
  const AuthSession({required this.accessToken, required this.userId});

  final String accessToken;
  final String userId;
}

Future<void> main() async {
  const url = String.fromEnvironment('SUPABASE_URL');
  const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  const passkey = String.fromEnvironment(
    'NOTERR_TEST_PASSKEY',
    defaultValue: 'codex-sync-smoke',
  );

  if (url.isEmpty || anonKey.isEmpty) {
    throw StateError('SUPABASE_URL and SUPABASE_ANON_KEY are required.');
  }

  final credentials = await VaultCrypto.syncCredentials(passkey);
  final sessionA = await _signInOrCreate(
    url,
    anonKey,
    credentials.email,
    credentials.password,
  );
  final sessionB = await _signInOrCreate(
    url,
    anonKey,
    credentials.email,
    credentials.password,
  );

  if (sessionA.userId != sessionB.userId) {
    throw StateError('Passkey generated different Supabase users.');
  }

  final salt = await _getOrCreateSalt(url, anonKey, sessionA);
  final key = await VaultCrypto.deriveKey(passphrase: passkey, salt: salt);

  final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
  final aBody = 'smoke from device A $stamp';
  final bBody = 'smoke from device B $stamp';
  final noteA = Note.blank('smoke-device-a').copyWith(
    title: 'Smoke A',
    body: aBody,
    boardName: 'Smoke',
  );
  final noteB = Note.blank('smoke-device-b').copyWith(
    title: 'Smoke B',
    body: bBody,
    boardName: 'Smoke',
  );

  await _push(url, anonKey, sessionA, noteA, key, 'smoke-device-a');
  final pulledByB = await _pull(url, anonKey, sessionB, key);
  if (!pulledByB.any((note) => note.body == aBody)) {
    throw StateError('Device B could not pull/decrypt Device A note.');
  }

  await _push(url, anonKey, sessionB, noteB, key, 'smoke-device-b');
  final pulledByA = await _pull(url, anonKey, sessionA, key);
  if (!pulledByA.any((note) => note.body == bBody)) {
    throw StateError('Device A could not pull/decrypt Device B note.');
  }

  await _delete(url, anonKey, sessionA, noteA.id);
  await _delete(url, anonKey, sessionA, noteB.id);

  print(
      'SYNC_SMOKE_OK pulledByA=${pulledByA.length} pulledByB=${pulledByB.length}');
}

Future<AuthSession> _signInOrCreate(
  String url,
  String anonKey,
  String email,
  String password,
) async {
  var response = await _authPost(
    url,
    anonKey,
    '/auth/v1/token?grant_type=password',
    {'email': email, 'password': password},
  );
  if (response.statusCode != 200) {
    final lower = response.body.toLowerCase();
    if (!lower.contains('invalid') && !lower.contains('credentials')) {
      throw StateError(
          'Sign-in failed: ${response.statusCode} ${response.body}');
    }
    response = await _authPost(
      url,
      anonKey,
      '/auth/v1/signup',
      {'email': email, 'password': password},
    );
    if (response.statusCode != 200) {
      throw StateError(
          'Sign-up failed: ${response.statusCode} ${response.body}');
    }
    response = await _authPost(
      url,
      anonKey,
      '/auth/v1/token?grant_type=password',
      {'email': email, 'password': password},
    );
    if (response.statusCode != 200) {
      throw StateError(
        'Sign-in after sign-up failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final user = json['user'] as Map<String, dynamic>?;
  return AuthSession(
    accessToken: json['access_token'] as String,
    userId: user?['id'] as String? ?? '',
  );
}

Future<String> _getOrCreateSalt(
  String url,
  String anonKey,
  AuthSession session,
) async {
  final existing = await _restGet(
    url,
    anonKey,
    session,
    '/rest/v1/noterr_profiles?select=vault_salt&user_id=eq.${session.userId}',
  );
  if (existing.statusCode != 200) {
    throw StateError(
        'Profile select failed: ${existing.statusCode} ${existing.body}');
  }
  final rows = jsonDecode(existing.body) as List<dynamic>;
  if (rows.isNotEmpty) {
    final row = rows.first as Map<String, dynamic>;
    final salt = row['vault_salt'] as String?;
    if (salt != null && salt.isNotEmpty) return salt;
  }

  final salt = VaultCrypto.randomSalt();
  final created = await _restPost(
    url,
    anonKey,
    session,
    '/rest/v1/noterr_profiles',
    {'user_id': session.userId, 'vault_salt': salt},
    prefer: 'resolution=merge-duplicates',
  );
  if (created.statusCode < 200 || created.statusCode >= 300) {
    throw StateError(
        'Profile upsert failed: ${created.statusCode} ${created.body}');
  }
  return salt;
}

Future<void> _push(
  String url,
  String anonKey,
  AuthSession session,
  Note note,
  SecretKey key,
  String deviceId,
) async {
  final payload = await VaultCrypto.encryptJson(note.toJson(), key);
  final response = await _restPost(
    url,
    anonKey,
    session,
    '/rest/v1/noterr_notes',
    {
      'id': note.id,
      'owner_id': session.userId,
      'encrypted_payload': payload.cipherText,
      'nonce': payload.nonce,
      'mac': payload.mac,
      'payload_version': 1,
      'revision': note.revision,
      'device_id': deviceId,
      'deleted_at': note.deletedAt?.toIso8601String(),
    },
    prefer: 'resolution=merge-duplicates',
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError(
        'Note upsert failed: ${response.statusCode} ${response.body}');
  }
}

Future<List<Note>> _pull(
  String url,
  String anonKey,
  AuthSession session,
  SecretKey key,
) async {
  final response = await _restGet(
    url,
    anonKey,
    session,
    '/rest/v1/noterr_notes?select=*&owner_id=eq.${session.userId}&order=updated_at.desc',
  );
  if (response.statusCode != 200) {
    throw StateError(
        'Note pull failed: ${response.statusCode} ${response.body}');
  }
  final rows = jsonDecode(response.body) as List<dynamic>;
  final notes = <Note>[];
  for (final item in rows) {
    final row = item as Map<String, dynamic>;
    final payload = EncryptedPayload(
      cipherText: row['encrypted_payload'] as String,
      nonce: row['nonce'] as String,
      mac: row['mac'] as String,
    );
    final json = await VaultCrypto.decryptJson(payload, key);
    notes.add(Note.fromJson(json));
  }
  return notes;
}

Future<void> _delete(
  String url,
  String anonKey,
  AuthSession session,
  String noteId,
) async {
  await http.delete(
    Uri.parse('$url/rest/v1/noterr_notes?id=eq.$noteId'),
    headers: _headers(anonKey, session),
  );
}

Future<http.Response> _authPost(
  String url,
  String anonKey,
  String path,
  Map<String, Object?> body,
) {
  return http.post(
    Uri.parse('$url$path'),
    headers: {
      'apikey': anonKey,
      'authorization': 'Bearer $anonKey',
      'content-type': 'application/json',
    },
    body: jsonEncode(body),
  );
}

Future<http.Response> _restGet(
  String url,
  String anonKey,
  AuthSession session,
  String path,
) {
  return http.get(Uri.parse('$url$path'), headers: _headers(anonKey, session));
}

Future<http.Response> _restPost(
  String url,
  String anonKey,
  AuthSession session,
  String path,
  Map<String, Object?> body, {
  String? prefer,
}) {
  return http.post(
    Uri.parse('$url$path'),
    headers: {
      ..._headers(anonKey, session),
      'content-type': 'application/json',
      if (prefer != null) 'prefer': prefer,
    },
    body: jsonEncode(body),
  );
}

Map<String, String> _headers(String anonKey, AuthSession session) {
  return {
    'apikey': anonKey,
    'authorization': 'Bearer ${session.accessToken}',
  };
}
