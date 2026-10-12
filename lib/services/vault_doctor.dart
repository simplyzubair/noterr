import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import '../models/note.dart';
import 'local_vault.dart';
import 'vault_crypto.dart';

/// Diagnostic for a vault that refuses every passphrase.
///
/// A vault first written by a build with cloud sync was encrypted with the
/// salt cached from the server, while a local-only build derives its key from
/// [LocalVault.getOrCreateLocalSalt]. When those differ, the passphrase is
/// correct but the key is not, and the UI can only report a wrong PIN.
///
/// Reports which stored salt actually opens the vault. It prints no passphrase,
/// no salt and no note content, so the output is safe to paste into a log.
class VaultDoctor {
  VaultDoctor._();

  static Future<void> run(LocalVault vault) async {
    stdout.writeln('--- noterr vault doctor ---');

    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}noterr_vault.json');
    stdout.writeln('vault path   : ${file.path}');
    if (!await file.exists()) {
      stdout.writeln('vault        : MISSING - nothing to recover');
      return;
    }

    final payload = EncryptedPayload.fromJson(
      (jsonDecode(await file.readAsString()) as Map<String, dynamic>)['payload']
          as Map<String, dynamic>,
    );

    final saved = await vault.readSavedPassphrase();
    stdout.writeln('saved passphrase present: ${saved != null && saved.trim().isNotEmpty}');
    if (saved != null) {
      stdout.writeln('saved passphrase length : ${saved.trim().length}');
      stdout.writeln('saved passphrase digits : ${RegExp(r'^[0-9]+$').hasMatch(saved.trim())}');
    }

    final localSalt = await vault.getOrCreateLocalSalt();
    final cachedSalt = await vault.readCachedVaultSalt();
    stdout.writeln('local salt present : true');
    stdout.writeln('cached salt present: ${cachedSalt != null}');
    stdout.writeln('salts differ       : ${cachedSalt != null && cachedSalt != localSalt}');

    if (saved == null || saved.trim().isEmpty) {
      stdout.writeln('RESULT: no saved passphrase, cannot test salts here.');
      return;
    }

    for (final entry in {'local': localSalt, 'cached': cachedSalt}.entries) {
      final salt = entry.value;
      if (salt == null) continue;
      final ok = await _opens(payload, saved.trim(), salt);
      stdout.writeln('saved passphrase + ${entry.key} salt -> ${ok ? "OPENS" : "fails"}');
    }

    // Structure of every note: kind, day, flags and tick counts. No titles,
    // bodies or task text are printed.
    for (final entry in {'local': localSalt, 'cached': cachedSalt}.entries) {
      final salt = entry.value;
      if (salt == null || !await _opens(payload, saved.trim(), salt)) continue;
      final key = await VaultCrypto.deriveKey(passphrase: saved.trim(), salt: salt);
      final json = await VaultCrypto.decryptJson(payload, key);
      final notes = ((json['notes'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => Note.fromJson(Map<String, dynamic>.from(m)))
          .toList()
        ..sort((a, b) => a.dayKey.compareTo(b.dayKey));
      stdout.writeln('notes: ${notes.length}');
      for (final n in notes) {
        final done = n.checklist.where((i) => i.done).length;
        final carried = n.checklist.where((i) => i.carriedFrom != null).length;
        stdout.writeln(
          '${n.id.substring(0, 8)} board=${n.boardName.padRight(14)} '
          'day=${formatNoteDate(n.dayKey)} type=${n.type.name.padRight(9)} '
          'archived=${n.isArchived ? 1 : 0} deleted=${n.isDeleted ? 1 : 0} '
          'pinned=${n.isPinned ? 1 : 0} desktop=${n.popOnDesktop ? 1 : 0} '
          'widget=${n.showOnMobileWidget ? 1 : 0} '
          'tasks=${n.checklist.length} done=$done carried=$carried '
          'body=${n.body.trim().isEmpty ? 0 : 1} rev=${n.revision} '
          'dev=${n.deviceId.length >= 6 ? n.deviceId.substring(0, 6) : n.deviceId}',
        );
      }
      break;
    }

    stdout.writeln('--- end ---');
  }

  static Future<bool> _opens(
    EncryptedPayload payload,
    String passphrase,
    String salt,
  ) async {
    try {
      final key = await VaultCrypto.deriveKey(passphrase: passphrase, salt: salt);
      await AesGcm.with256bits().decrypt(
        SecretBox(
          base64Decode(payload.cipherText),
          nonce: base64Decode(payload.nonce),
          mac: Mac(base64Decode(payload.mac)),
        ),
        secretKey: key,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
