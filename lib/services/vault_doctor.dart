import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

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
