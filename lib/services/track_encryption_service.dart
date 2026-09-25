import 'dart:io';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypts/decrypts downloaded track files at rest (AES-256-CBC). The key
/// lives in the OS keychain/keystore via flutter_secure_storage — Keychain
/// on iOS/macOS, Keystore on Android, DPAPI on Windows — generated once on
/// first use and never written to disk alongside the audio files.
///
/// File format on disk: 16-byte IV followed by the AES-CBC ciphertext.
class TrackEncryptionService {
  static const _keyStorageKey = 'vasis_beats_track_encryption_key';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  enc.Key? _cachedKey;

  Future<enc.Key> _getOrCreateKey() async {
    final cached = _cachedKey;
    if (cached != null) return cached;

    final existing = await _secureStorage.read(key: _keyStorageKey);
    if (existing != null) {
      final key = enc.Key.fromBase64(existing);
      _cachedKey = key;
      return key;
    }

    final newKey = enc.Key.fromSecureRandom(32); // AES-256
    await _secureStorage.write(key: _keyStorageKey, value: newKey.base64);
    _cachedKey = newKey;
    return newKey;
  }

  /// Encrypts [plainFile] and writes the result to [encryptedFile]. Does
  /// not delete [plainFile] — the caller decides when that's safe (only
  /// after confirming the encrypted output is good).
  Future<void> encryptFile(File plainFile, File encryptedFile) async {
    final key = await _getOrCreateKey();
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

    final plainBytes = await plainFile.readAsBytes();
    final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);

    final out = BytesBuilder()
      ..add(iv.bytes)
      ..add(encrypted.bytes);
    await encryptedFile.writeAsBytes(out.toBytes(), flush: true);
  }

  /// Decrypts [encryptedFile] (as written by [encryptFile]) to [outputFile].
  Future<void> decryptFile(File encryptedFile, File outputFile) async {
    final key = await _getOrCreateKey();
    final bytes = await encryptedFile.readAsBytes();
    if (bytes.length <= 16) {
      throw StateError('Encrypted file is too short to contain an IV: ${encryptedFile.path}');
    }
    final iv = enc.IV(bytes.sublist(0, 16));
    final cipherBytes = bytes.sublist(16);

    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final decrypted = encrypter.decryptBytes(enc.Encrypted(Uint8List.fromList(cipherBytes)), iv: iv);
    await outputFile.writeAsBytes(decrypted, flush: true);
  }
}
