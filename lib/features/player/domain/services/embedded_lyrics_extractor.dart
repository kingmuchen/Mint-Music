import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class EmbeddedLyricsExtractor {
  static Future<String?> extract(String filePath) async {
    debugPrint('EmbeddedLyricsExtractor: extracting from $filePath');
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('EmbeddedLyricsExtractor: file does not exist');
        return null;
      }

      final ext = filePath.toLowerCase();
      if (ext.endsWith('.flac')) {
        return _extractFromFlac(filePath);
      } else if (ext.endsWith('.mp3')) {
        return _extractFromId3(filePath);
      } else {
        debugPrint('EmbeddedLyricsExtractor: unsupported format, trying ID3');
        return _extractFromId3(filePath);
      }
    } catch (e) {
      debugPrint('EmbeddedLyricsExtractor: error = $e');
      return null;
    }
  }

  static Future<String?> _extractFromFlac(String filePath) async {
    debugPrint('EmbeddedLyricsExtractor: extracting from FLAC');
    final file = File(filePath);
    final raf = await file.open(mode: FileMode.read);
    try {
      final header = await raf.read(4);
      if (header.length < 4) {
        debugPrint('EmbeddedLyricsExtractor: FLAC header too short');
        return null;
      }

      final magic = utf8.decode(header);
      if (magic != 'fLaC') {
        debugPrint('EmbeddedLyricsExtractor: not a FLAC file, got: $magic');
        return null;
      }

      bool lastBlock = false;
      while (!lastBlock) {
        final blockHeader = await raf.read(1);
        if (blockHeader.isEmpty) break;

        final headerByte = blockHeader[0];
        lastBlock = (headerByte & 0x80) != 0;
        final blockType = headerByte & 0x7F;

        final sizeBytes = await raf.read(3);
        if (sizeBytes.length < 3) break;
        final blockSize =
            (sizeBytes[0] << 16) | (sizeBytes[1] << 8) | sizeBytes[2];

        debugPrint(
          'EmbeddedLyricsExtractor: FLAC block type=$blockType, size=$blockSize, last=$lastBlock',
        );

        if (blockType == 4) {
          final blockData = await raf.read(blockSize);
          if (blockData.length >= blockSize) {
            final result = _parseVorbisComment(blockData);
            if (result != null) {
              debugPrint(
                'EmbeddedLyricsExtractor: found lyrics in Vorbis comment',
              );
              return result;
            }
          }
        } else {
          await raf.setPosition(await raf.position() + blockSize);
        }
      }

      debugPrint('EmbeddedLyricsExtractor: no lyrics found in FLAC');
      return null;
    } finally {
      await raf.close();
    }
  }

  static String? _parseVorbisComment(Uint8List data) {
    if (data.length < 8) return null;

    int offset = 0;

    final vendorLength = _readLE32(data, offset);
    offset += 4 + vendorLength;
    if (offset + 4 > data.length) return null;

    final commentCount = _readLE32(data, offset);
    offset += 4;
    debugPrint('EmbeddedLyricsExtractor: Vorbis has $commentCount comments');

    for (int i = 0; i < commentCount && offset < data.length; i++) {
      if (offset + 4 > data.length) break;
      final commentLength = _readLE32(data, offset);
      offset += 4;

      if (offset + commentLength > data.length) break;

      final commentBytes = data.sublist(offset, offset + commentLength);
      offset += commentLength;

      try {
        final comment = utf8.decode(commentBytes);
        final lowerComment = comment.toLowerCase();

        if (lowerComment.startsWith('lyrics=')) {
          final lyrics = comment.substring(7);
          debugPrint(
            'EmbeddedLyricsExtractor: found LYRICS tag, length=${lyrics.length}',
          );
          return lyrics;
        }
        if (lowerComment.startsWith('unsyncedlyrics=')) {
          final lyrics = comment.substring(15);
          debugPrint(
            'EmbeddedLyricsExtractor: found UNSYNCEDLYRICS tag, length=${lyrics.length}',
          );
          return lyrics;
        }
        if (lowerComment.startsWith('lyrics-')) {
          final eqIndex = comment.indexOf('=');
          if (eqIndex > 0) {
            final lyrics = comment.substring(eqIndex + 1);
            debugPrint(
              'EmbeddedLyricsExtractor: found LYRICS-* tag, length=${lyrics.length}',
            );
            return lyrics;
          }
        }
      } catch (e) {
        debugPrint('EmbeddedLyricsExtractor: failed to decode comment: $e');
      }
    }

    return null;
  }

  static int _readLE32(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  static Future<String?> _extractFromId3(String filePath) async {
    debugPrint('EmbeddedLyricsExtractor: extracting from ID3');
    final file = File(filePath);
    final raf = await file.open(mode: FileMode.read);
    try {
      final header = await raf.read(10);
      if (header.length < 10) {
        debugPrint('EmbeddedLyricsExtractor: header too short');
        return null;
      }

      final id3 = utf8.decode(header.sublist(0, 3));
      if (id3 != 'ID3') {
        debugPrint('EmbeddedLyricsExtractor: no ID3 tag found, got: $id3');
        return null;
      }

      final versionMajor = header[3];
      final tagSize = _synchsafeToInt(header.sublist(6, 10));
      debugPrint(
        'EmbeddedLyricsExtractor: ID3v2.$versionMajor, tagSize=$tagSize',
      );

      final tagBytes = await raf.read(tagSize);
      if (tagBytes.length < tagSize) {
        debugPrint('EmbeddedLyricsExtractor: tag bytes too short');
        return null;
      }

      final result = _parseFrames(tagBytes, versionMajor);
      debugPrint(
        'EmbeddedLyricsExtractor: parse result = ${result?.isEmpty ?? true ? "null/empty" : "has ${result!.length} chars"}',
      );
      return result;
    } finally {
      await raf.close();
    }
  }

  static int _synchsafeToInt(Uint8List bytes) {
    int value = 0;
    for (int i = 0; i < bytes.length; i++) {
      value = (value << 7) | (bytes[i] & 0x7F);
    }
    return value;
  }

  static int _bytesToInt(Uint8List bytes) {
    int value = 0;
    for (int i = 0; i < bytes.length; i++) {
      value = (value << 8) | bytes[i];
    }
    return value;
  }

  static String? _parseFrames(Uint8List data, int versionMajor) {
    int offset = 0;
    int frameCount = 0;

    while (offset + 10 <= data.length) {
      final frameId = utf8.decode(data.sublist(offset, offset + 4));

      if (frameId.codeUnitAt(0) == 0) break;

      final frameSize = versionMajor >= 4
          ? _synchsafeToInt(data.sublist(offset + 4, offset + 8))
          : _bytesToInt(data.sublist(offset + 4, offset + 8));

      if (frameSize <= 0 || offset + 10 + frameSize > data.length) break;

      frameCount++;
      debugPrint(
        'EmbeddedLyricsExtractor: frame #$frameCount = $frameId, size=$frameSize',
      );

      if (frameId == 'USLT') {
        debugPrint('EmbeddedLyricsExtractor: found USLT frame!');
        return _parseUsltFrame(data, offset + 10, frameSize);
      }

      offset += 10 + frameSize;
    }

    debugPrint(
      'EmbeddedLyricsExtractor: scanned $frameCount frames, no USLT found',
    );
    return null;
  }

  static String? _parseUsltFrame(Uint8List data, int offset, int size) {
    debugPrint('EmbeddedLyricsExtractor: parsing USLT frame, size=$size');
    if (size < 5) {
      debugPrint('EmbeddedLyricsExtractor: USLT frame too small');
      return null;
    }

    final encoding = data[offset];
    debugPrint('EmbeddedLyricsExtractor: encoding=$encoding');

    int pos = offset + 4;

    if (encoding == 1) {
      while (pos + 1 < offset + size) {
        if (data[pos] == 0 && data[pos + 1] == 0) {
          pos += 2;
          break;
        }
        pos += 2;
      }
    } else {
      while (pos < offset + size) {
        if (data[pos] == 0) {
          pos += 1;
          break;
        }
        pos += 1;
      }
    }

    if (pos >= offset + size) {
      debugPrint('EmbeddedLyricsExtractor: no text found in USLT');
      return null;
    }

    final textBytes = data.sublist(pos, offset + size);
    debugPrint('EmbeddedLyricsExtractor: textBytes length=${textBytes.length}');

    try {
      String result;
      if (encoding == 1) {
        if (textBytes.length >= 2 &&
            textBytes[0] == 0xFF &&
            textBytes[1] == 0xFE) {
          result = _decodeUtf16Le(textBytes);
        } else if (textBytes.length >= 2 &&
            textBytes[0] == 0xFE &&
            textBytes[1] == 0xFF) {
          result = _decodeUtf16Be(textBytes);
        } else {
          result = _decodeUtf16Le(textBytes);
        }
      } else if (encoding == 2) {
        result = _decodeUtf16Be(textBytes);
      } else if (encoding == 3) {
        result = utf8.decode(textBytes);
      } else {
        result = utf8.decode(textBytes);
      }
      final trimmed = result.replaceAll(RegExp(r'\x00'), '').trim();
      debugPrint(
        'EmbeddedLyricsExtractor: decoded text length=${trimmed.length}',
      );
      debugPrint(
        'EmbeddedLyricsExtractor: text preview = ${trimmed.substring(0, trimmed.length > 100 ? 100 : trimmed.length)}',
      );
      return trimmed.isNotEmpty ? trimmed : null;
    } catch (e) {
      debugPrint('EmbeddedLyricsExtractor: decode error = $e');
      try {
        final result = utf8.decode(textBytes, allowMalformed: true);
        final trimmed = result.replaceAll(RegExp(r'\x00'), '').trim();
        debugPrint(
          'EmbeddedLyricsExtractor: fallback decode success, length=${trimmed.length}',
        );
        return trimmed.isNotEmpty ? trimmed : null;
      } catch (e2) {
        debugPrint('EmbeddedLyricsExtractor: fallback decode error = $e2');
        return null;
      }
    }
  }

  static String _decodeUtf16Le(Uint8List bytes) {
    final chars = <int>[];
    for (int i = 0; i < bytes.length - 1; i += 2) {
      final char = bytes[i] | (bytes[i + 1] << 8);
      if (char != 0) chars.add(char);
    }
    return String.fromCharCodes(chars);
  }

  static String _decodeUtf16Be(Uint8List bytes) {
    final chars = <int>[];
    for (int i = 0; i < bytes.length - 1; i += 2) {
      final char = (bytes[i] << 8) | bytes[i + 1];
      if (char != 0) chars.add(char);
    }
    return String.fromCharCodes(chars);
  }
}
