import 'dart:io';
import 'dart:math';

import '../models/song.dart';

class QualitySizeFormatter {
  static const _estimatedBitrates = <String, int>{
    '128k': 128000,
    '192k': 192000,
    '320k': 320000,
    'flac': 900000,
    'flac24bit': 2300000,
    'hires': 2800000,
    'atmos': 768000,
    'master': 3200000,
  };

  static String sizeText(Song? song, String quality) {
    if (song == null) return '--';

    final actual = _actualSizeText(song, quality);
    if (actual != null) return actual;

    final localSize = _localFileSize(song);
    if (localSize != null && song.isLocal) {
      return _formatBytes(localSize);
    }

    final seconds = song.duration;
    if (seconds <= 0) return '--';

    final bitrate = _estimatedBitrates[quality] ?? song.bitrate;
    if (bitrate == null || bitrate <= 0) return '--';

    return '~${_formatBytes(seconds * bitrate / 8)}';
  }

  static String descriptionWithSize(
    Song? song,
    String quality,
    String description,
  ) {
    final size = sizeText(song, quality);
    if (size == '--') return description;
    if (description.isEmpty) return size;
    return '$description - $size';
  }

  static String? _actualSizeText(Song song, String quality) {
    final lx = song.lx;
    if (lx == null || lx.isEmpty) return null;

    final normalizedQuality = _normalizeQuality(quality);
    final candidates = <dynamic>[
      _fromTypeList(lx['types'], normalizedQuality),
      _fromQualityMap(lx['_types'], normalizedQuality),
      _fromQualityMap(lx['typeMap'], normalizedQuality),
      _fromQualityMap(lx['typeUrl'], normalizedQuality),
      _fromFlatKeys(lx, normalizedQuality),
    ];

    for (final value in candidates) {
      final text = _sizeValueToText(value);
      if (text != null) return text;
    }
    return null;
  }

  static dynamic _fromTypeList(dynamic value, String normalizedQuality) {
    if (value is! List) return null;
    for (final item in value) {
      if (item is Map) {
        final type =
            item['type'] ?? item['quality'] ?? item['id'] ?? item['name'];
        if (_normalizeQuality(type?.toString() ?? '') == normalizedQuality) {
          return item['size'] ?? item['fileSize'] ?? item['filesize'];
        }
      } else if (_normalizeQuality(item.toString()) == normalizedQuality) {
        return null;
      }
    }
    return null;
  }

  static dynamic _fromQualityMap(dynamic value, String normalizedQuality) {
    if (value is! Map) return null;
    for (final entry in value.entries) {
      if (_normalizeQuality(entry.key.toString()) != normalizedQuality) {
        continue;
      }
      final item = entry.value;
      if (item is Map) {
        return item['size'] ?? item['fileSize'] ?? item['filesize'];
      }
      return item;
    }
    return null;
  }

  static dynamic _fromFlatKeys(
    Map<String, dynamic> lx,
    String normalizedQuality,
  ) {
    final keys = <String>[
      'size$normalizedQuality',
      'size_$normalizedQuality',
      '${normalizedQuality}Size',
      '${normalizedQuality}_size',
      'fileSize$normalizedQuality',
      'filesize$normalizedQuality',
    ];

    const aliases = {
      '128k': ['size128', 'size128k', 'size_l', 'sizeM4a'],
      '192k': ['size192', 'size192k'],
      '320k': ['size320', 'size320k', 'size_h', 'sizeMp3'],
      'flac': ['sizeflac', 'size_flac', 'size_sq', 'sizeApe'],
      'flac24bit': ['sizeflac24', 'sizeflac24bit', 'size_24bit'],
      'hires': ['sizehires', 'size_hr', 'sizeHires'],
      'atmos': ['sizeatmos', 'size_dolby', 'sizeDolby'],
      'master': ['sizemaster', 'size_jm', 'sizeMaster'],
    };

    for (final key in [...keys, ...?aliases[normalizedQuality]]) {
      for (final entry in lx.entries) {
        if (entry.key.toLowerCase() == key.toLowerCase()) {
          return entry.value;
        }
      }
    }
    return null;
  }

  static int? _localFileSize(Song song) {
    final path = song.filePath ?? song.sourceUrl;
    if (path == null || path.startsWith('http')) return null;
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      return file.lengthSync();
    } catch (_) {
      return null;
    }
  }

  static String? _sizeValueToText(dynamic value) {
    if (value == null) return null;
    if (value is num && value > 0) return _formatBytes(value);

    final text = value.toString().trim();
    if (text.isEmpty || text == '0') return null;
    final numeric = num.tryParse(text);
    if (numeric != null && numeric > 0) return _formatBytes(numeric);

    final normalized = text.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(
      r'^\d+(\.\d+)?(B|KB|MB|GB|TB)$',
      caseSensitive: false,
    ).hasMatch(normalized)) {
      return normalized.toUpperCase();
    }
    return null;
  }

  static String _formatBytes(num bytes) {
    if (bytes <= 0) return '0B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    final index = min((log(bytes) / log(1024)).floor(), units.length - 1);
    final value = bytes / pow(1024, index);
    if (index == 0) return '${value.round()}${units[index]}';
    return '${value.toStringAsFixed(2)}${units[index]}';
  }

  static String _normalizeQuality(String quality) {
    final q = quality.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (q == '128' || q.contains('128')) return '128k';
    if (q == '192' || q.contains('192')) return '192k';
    if (q == '320' || q.contains('320')) return '320k';
    if (q.contains('24') || q.contains('flac24')) return 'flac24bit';
    if (q.contains('hires') || q.contains('hr')) return 'hires';
    if (q.contains('atmos') || q.contains('dolby') || q == 'db') return 'atmos';
    if (q.contains('master') || q == 'jm') return 'master';
    if (q.contains('flac') || q.contains('lossless') || q == 'sq') {
      return 'flac';
    }
    return q;
  }
}
