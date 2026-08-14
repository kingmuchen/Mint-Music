import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:pointycastle/export.dart';

class CeruMusicPlaylistImporter {
  static const String _secretKey = 'CeruMusic-PlaylistSecretKey';

  static List<Map<String, dynamic>> importFromFile(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('文件不存在');
    }

    final ext = _getExtension(filePath);
    final bytes = file.readAsBytesSync();

    if (ext == 'cpl') {
      final encryptedText = utf8.decode(bytes);
      return decryptPlaylist(encryptedText);
    } else if (ext == 'cmpl') {
      final decompressedText = _gunzipToString(bytes);
      return decryptPlaylist(decompressedText);
    } else if (ext == 'json') {
      final jsonText = utf8.decode(bytes);
      return _parseJsonPlaylist(jsonText);
    } else {
      throw Exception('不支持的文件类型: $ext');
    }
  }

  static Future<List<Map<String, dynamic>>> importFromFileAsync(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在');
    }

    final ext = _getExtension(filePath);
    final bytes = await file.readAsBytes();

    if (ext == 'cpl') {
      final encryptedText = utf8.decode(bytes);
      return decryptPlaylist(encryptedText);
    } else if (ext == 'cmpl') {
      final decompressedText = await _gunzipToStringAsync(bytes);
      return decryptPlaylist(decompressedText);
    } else if (ext == 'json') {
      final jsonText = utf8.decode(bytes);
      return _parseJsonPlaylist(jsonText);
    } else {
      throw Exception('不支持的文件类型: $ext');
    }
  }

  static List<Map<String, dynamic>> decryptPlaylist(String encryptedData) {
    try {
      final decrypted = _aesDecrypt(encryptedData, _secretKey);
      final playlist = jsonDecode(decrypted) as List<dynamic>;
      return playlist.cast<Map<String, dynamic>>();
    } catch (e) {
      throw Exception('解密失败或数据格式不正确: $e');
    }
  }

  static bool validateImportedPlaylist(List<Map<String, dynamic>> playlist) {
    if (playlist.isEmpty) return false;

    for (final song in playlist) {
      if (!_validateSongItem(song)) {
        return false;
      }
    }
    return true;
  }

  static bool _validateSongItem(Map<String, dynamic> song) {
    final requiredFields = ['songmid', 'name', 'singer', 'img', 'interval', 'source'];
    for (final field in requiredFields) {
      if (!song.containsKey(field)) return false;
    }

    if (song['name'] == null) return false;
    if (song['singer'] == null) return false;
    if (song['interval'] == null) return false;
    if (song['source'] == null) return false;

    return true;
  }

  static String _aesDecrypt(String encryptedBase64, String password) {
    final encryptedBytes = base64.decode(encryptedBase64);

    if (encryptedBytes.length < 16) {
      throw Exception('加密数据格式不正确');
    }

    final saltedPrefix = utf8.decode(encryptedBytes.sublist(0, 8));
    if (saltedPrefix != 'Salted__') {
      throw Exception('加密数据格式不正确，缺少Salted__前缀');
    }

    final salt = encryptedBytes.sublist(8, 16);
    final ciphertext = encryptedBytes.sublist(16);

    final keySize = 32;
    final ivSize = 16;
    final keyAndIv = _evpBytesToKey(password, salt, keySize + ivSize);
    final key = keyAndIv.sublist(0, keySize);
    final iv = keyAndIv.sublist(keySize, keySize + ivSize);

    final cipher = CBCBlockCipher(AESEngine());
    final params = ParametersWithIV(KeyParameter(key), iv);
    cipher.init(false, params);

    final paddedCipher = _PKCS7PaddedBlockCipher(cipher);
    paddedCipher.init(false, params);

    final output = Uint8List(ciphertext.length);
    var offset = 0;
    while (offset < ciphertext.length) {
      offset += paddedCipher.processBlock(ciphertext, offset, output, offset);
    }

    final padLen = paddedCipher.padCount(output);
    return utf8.decode(output.sublist(0, output.length - padLen));
  }

  static Uint8List _evpBytesToKey(String password, Uint8List salt, int keyLen) {
    final passwordBytes = utf8.encode(password);
    var result = Uint8List(0);
    var d = Uint8List(0);

    while (result.length < keyLen) {
      if (d.isEmpty) {
        d = Uint8List.fromList([...passwordBytes, ...salt]);
      } else {
        d = Uint8List.fromList([...d, ...passwordBytes, ...salt]);
      }

      d = _md5Hash(d);
      result = Uint8List.fromList([...result, ...d]);
    }

    return result.sublist(0, keyLen);
  }

  static Uint8List _md5Hash(Uint8List data) {
    final digest = MD5Digest();
    final output = Uint8List(digest.digestSize);
    digest.update(data, 0, data.length);
    digest.doFinal(output, 0);
    return output;
  }

  static String _gunzipToString(Uint8List compressedData) {
    final decompressor = GZipDecoder();
    final decompressed = decompressor.decodeBytes(compressedData);
    return utf8.decode(decompressed);
  }

  static Future<String> _gunzipToStringAsync(Uint8List compressedData) async {
    return _gunzipToString(compressedData);
  }

  static String _getExtension(String path) {
    final parts = path.split('.');
    if (parts.length > 1) {
      return parts.last.toLowerCase();
    }
    return '';
  }

  static List<Map<String, dynamic>> _parseJsonPlaylist(String jsonText) {
    try {
      final data = jsonDecode(jsonText);
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      } else if (data is Map) {
        if (data.containsKey('songs')) {
          return (data['songs'] as List).cast<Map<String, dynamic>>();
        }
        return [data.cast<String, dynamic>()];
      }
      throw Exception('JSON 格式不正确');
    } catch (e) {
      throw Exception('解析 JSON 失败: $e');
    }
  }
}

class _PKCS7PaddedBlockCipher {
  final BlockCipher _cipher;
  int _padCount = 0;

  _PKCS7PaddedBlockCipher(this._cipher);

  void init(bool forEncryption, CipherParameters params) {
    _cipher.init(forEncryption, params);
  }

  int processBlock(Uint8List input, int inputOffset, Uint8List output, int outputOffset) {
    return _cipher.processBlock(input, inputOffset, output, outputOffset);
  }

  int padCount(Uint8List output) {
    final lastByte = output[output.length - 1];
    _padCount = lastByte;

    if (_padCount < 1 || _padCount > 16) {
      return 0;
    }

    for (var i = output.length - _padCount; i < output.length; i++) {
      if (output[i] != _padCount) {
        return 0;
      }
    }

    return _padCount;
  }
}