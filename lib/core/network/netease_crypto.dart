import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';

class NeteaseCrypto {
  static final _iv = encrypt.IV.fromUtf8('0102030405060708');
  static final _presetKey = encrypt.Key.fromUtf8('0CoJUm6Qyw8W8jud');
  static final _linuxapiKey = encrypt.Key.fromUtf8('rFgB&h#%2?^eDg:Q');
  static final _eapiKey = encrypt.Key.fromUtf8('e82ckenh8dichen8');
  static const _base62 = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  static const _publicKeyPem = '-----BEGIN PUBLIC KEY-----\nMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDgtQn2JZ34ZC28NWYpAUd98iZ37BUrX/aKzmFbt7clFSs6sXqHauqKWqdtLkF2KexO40H1YTX8z2lSgBBOAxLsvaklV8k4cBFK9snQXE9/DDaFt6Rr7iVZMldczhC0JNgTz+SHXT6CBHuX3e9SdB1Ua44oncaTWz7OBGLbCiK45wIDAQAB\n-----END PUBLIC KEY-----';

  static Map<String, String> weapi(Map<String, dynamic> object) {
    final text = jsonEncode(object);
    final secretKey = _generateSecretKey();
    final firstEncrypt = _aesEncrypt(text, _presetKey, _iv, 'CBC');
    final secondEncrypt = _aesEncrypt(firstEncrypt, encrypt.Key(secretKey), _iv, 'CBC');
    final encSecKey = _rsaEncrypt(secretKey.reversed.toList());
    return {
      'params': secondEncrypt,
      'encSecKey': encSecKey,
    };
  }

  static Map<String, String> linuxapi(Map<String, dynamic> object) {
    final text = jsonEncode(object);
    final encipher = encrypt.Encrypter(encrypt.AES(_linuxapiKey, mode: encrypt.AESMode.ecb));
    final encrypted = encipher.encrypt(text, iv: null);
    return {
      'eparams': encrypted.base64.toUpperCase(),
    };
  }

  static Map<String, String> eapi(String url, Map<String, dynamic> object) {
    final text = jsonEncode(object);
    final message = 'nobody${url}use${text}md5forencrypt';
    final digest = md5.convert(utf8.encode(message)).toString();
    final data = '$url-36cd479b6b5-$text-36cd479b6b5-$digest';
    final encipher = encrypt.Encrypter(encrypt.AES(_eapiKey, mode: encrypt.AESMode.ecb));
    final encrypted = encipher.encrypt(data, iv: null);
    return {
      'params': encrypted.base64.toUpperCase(),
    };
  }

  static Uint8List _generateSecretKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(16, (_) => _base62.codeUnitAt(random.nextInt(62))),
    );
  }

  static String _aesEncrypt(String text, encrypt.Key key, encrypt.IV iv, String mode) {
    final aesMode = mode == 'CBC' ? encrypt.AESMode.cbc : encrypt.AESMode.ecb;
    final encipher = encrypt.Encrypter(encrypt.AES(key, mode: aesMode));
    final encrypted = encipher.encrypt(text, iv: mode == 'CBC' ? iv : null);
    return encrypted.base64;
  }

  static String _rsaEncrypt(List<int> data) {
    final parser = encrypt.RSAKeyParser();
    final key = parser.parse(_publicKeyPem) as RSAPublicKey;
    final cipher = PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(key));
    final input = Uint8List(128);
    input.setRange(128 - data.length, 128, data);
    final output = cipher.process(input);
    return hex.encode(output);
  }
}