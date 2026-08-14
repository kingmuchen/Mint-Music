import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// Secret key used by CeruMusic for .cmpl AES encryption.
const String _cmplSecretKey = 'CeruMusic-PlaylistSecretKey';

/// Magic prefix in CryptoJS's OpenSSL-compatible salted format.
const String _saltedPrefix = 'Salted__';

/// Derive key (32 bytes) and IV (16 bytes) using CryptoJS-compatible EvpKDF
/// (MD5-based key derivation). Replicates CryptoJS's EvpKDF exactly.
List<int> _evpKDF(String password, List<int> salt, int keySize, int ivSize) {
  final passwordBytes = utf8.encode(password);
  final totalBytes = keySize + ivSize;

  List<int> derived = [];
  List<int>? previousHash;

  while (derived.length < totalBytes) {
    final hashInput = <int>[];
    if (previousHash != null) {
      hashInput.addAll(previousHash);
    }
    hashInput.addAll(passwordBytes);
    hashInput.addAll(salt);

    final hash = md5.convert(hashInput);
    previousHash = hash.bytes;
    derived.addAll(previousHash);
  }

  return derived;
}

/// Encrypt [plaintext] using AES-256-CBC with CryptoJS-compatible salted format.
///
/// Returns a base64 string containing `Salted__` + 8-byte salt + ciphertext,
/// matching the output of `CryptoJS.AES.encrypt(data, password).toString()`.
String _aesEncryptCryptoJS(String plaintext, String password) {
  // Generate random 8-byte salt
  final salt = List<int>.generate(8, (_) => Random.secure().nextInt(256));

  // Derive key (32 bytes) and IV (16 bytes) via EvpKDF
  final derived = _evpKDF(password, salt, 32, 16);
  final keyBytes = Uint8List.fromList(derived.sublist(0, 32));
  final ivBytes = Uint8List.fromList(derived.sublist(32, 48));

  // Encrypt with AES-256-CBC (PKCS7 padding by default)
  final key = enc.Key(keyBytes);
  final iv = enc.IV(ivBytes);
  final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  final encrypted = encrypter.encrypt(plaintext, iv: iv);
  final ciphertextBytes = encrypted.bytes;

  // Combine: Salted__ + salt + ciphertext → base64
  final combined = <int>[];
  combined.addAll(utf8.encode(_saltedPrefix));
  combined.addAll(salt);
  combined.addAll(ciphertextBytes.toList());
  return base64.encode(combined);
}

/// Encode [jsonData] into the .cmpl format (AES-encrypted + gzip compressed),
/// fully compatible with CeruMusic's .cmpl files.
///
/// Returns the raw bytes ready to be written to a .cmpl file.
List<int> encodeCmpl(String jsonData) {
  // 1. AES encrypt (CryptoJS-compatible format → base64 string)
  final encryptedBase64 = _aesEncryptCryptoJS(jsonData, _cmplSecretKey);

  // 2. Gzip compress the base64 string
  final encryptedBytes = utf8.encode(encryptedBase64);
  return gzip.encode(encryptedBytes);
}

/// Decode a .cmpl file (gzip decompress + AES decrypt) back to JSON string.
///
/// Compatible with CeruMusic's .cmpl export format.
String decodeCmpl(List<int> cmplBytes) {
  // 1. Gzip decompress
  final decompressed = gzip.decode(cmplBytes);
  final encryptedBase64 = utf8.decode(decompressed);

  // 2. Decrypt AES (CryptoJS-compatible format)
  return _aesDecryptCryptoJS(encryptedBase64, _cmplSecretKey);
}

/// Decrypt a CryptoJS-format base64 string back to plaintext.
String _aesDecryptCryptoJS(String encryptedBase64, String password) {
  // Decode base64 → Salted__ + salt (8) + ciphertext
  final combined = base64.decode(encryptedBase64);
  final saltedHeader = utf8.decode(combined.sublist(0, 8));
  if (saltedHeader != _saltedPrefix) {
    throw FormatException('Invalid .cmpl format: missing Salted__ header');
  }
  final salt = combined.sublist(8, 16);
  final ciphertextBytes = combined.sublist(16);

  // Derive key and IV from password + salt (same as encryption)
  final derived = _evpKDF(password, salt, 32, 16);
  final keyBytes = Uint8List.fromList(derived.sublist(0, 32));
  final ivBytes = Uint8List.fromList(derived.sublist(32, 48));

  // Decrypt
  final key = enc.Key(keyBytes);
  final iv = enc.IV(ivBytes);
  final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  return encrypter.decrypt(enc.Encrypted(Uint8List.fromList(ciphertextBytes)), iv: iv);
}
