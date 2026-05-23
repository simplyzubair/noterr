import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class EncryptedPayload {
  const EncryptedPayload({
    required this.cipherText,
    required this.nonce,
    required this.mac,
  });

  factory EncryptedPayload.fromJson(Map<String, dynamic> json) {
    return EncryptedPayload(
      cipherText: json['cipherText'] as String,
      nonce: json['nonce'] as String,
      mac: json['mac'] as String,
    );
  }

  final String cipherText;
  final String nonce;
  final String mac;

  Map<String, dynamic> toJson() => {
        'cipherText': cipherText,
        'nonce': nonce,
        'mac': mac,
      };
}

class VaultCrypto {
  VaultCrypto._();

  static final _random = Random.secure();
  static final _aesGcm = AesGcm.with256bits();
  static final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  );

  static String randomSalt() {
    final bytes = Uint8List.fromList(
      List<int>.generate(24, (_) => _random.nextInt(256)),
    );
    return base64Encode(bytes);
  }

  static Future<SecretKey> deriveKey({
    required String passphrase,
    required String salt,
  }) {
    return _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: base64Decode(salt),
    );
  }

  static Future<EncryptedPayload> encryptJson(
    Map<String, dynamic> json,
    SecretKey key,
  ) async {
    final bytes = utf8.encode(jsonEncode(json));
    final box = await _aesGcm.encrypt(bytes, secretKey: key);
    return EncryptedPayload(
      cipherText: base64Encode(box.cipherText),
      nonce: base64Encode(box.nonce),
      mac: base64Encode(box.mac.bytes),
    );
  }

  static Future<Map<String, dynamic>> decryptJson(
    EncryptedPayload payload,
    SecretKey key,
  ) async {
    final box = SecretBox(
      base64Decode(payload.cipherText),
      nonce: base64Decode(payload.nonce),
      mac: Mac(base64Decode(payload.mac)),
    );
    final clearBytes = await _aesGcm.decrypt(box, secretKey: key);
    return jsonDecode(utf8.decode(clearBytes)) as Map<String, dynamic>;
  }
}
