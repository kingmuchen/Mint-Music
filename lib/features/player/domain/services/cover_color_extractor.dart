import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../models/song.dart';
import '../../application/playback_controller.dart';

class CoverColorResult {
  final Color dominantColor;
  final Color lightColor;
  final bool useDarkText;

  const CoverColorResult({
    required this.dominantColor,
    required this.lightColor,
    required this.useDarkText,
  });

  static const CoverColorResult defaultResult = CoverColorResult(
    dominantColor: Color(0xFF333333),
    lightColor: Color(0xE6FFFFFF),
    useDarkText: false,
  );
}

int _extractDominantColor(Uint8List rgbaBytes) {
  final pixelCount = rgbaBytes.length ~/ 4;
  int rSum = 0, gSum = 0, bSum = 0;
  int count = 0;
  final step = pixelCount > 8000 ? (pixelCount / 4000).floor().clamp(1, 20) : 1;

  for (int i = 0; i < pixelCount; i += step) {
    final offset = i * 4;
    final r = rgbaBytes[offset];
    final g = rgbaBytes[offset + 1];
    final b = rgbaBytes[offset + 2];
    final a = rgbaBytes[offset + 3];
    if (a < 128) continue;
    final brightness = (r * 299 + g * 587 + b * 114) ~/ 1000;
    if (brightness < 25 || brightness > 245) continue;
    rSum += r;
    gSum += g;
    bSum += b;
    count++;
  }

  if (count == 0) return 0xFF333333;
  return 0xFF000000 |
      ((rSum ~/ count) << 16) |
      ((gSum ~/ count) << 8) |
      (bSum ~/ count);
}

class CoverColorExtractor {
  static Future<CoverColorResult> extract(ImageProvider imageProvider) async {
    try {
      final imageStream = imageProvider.resolve(const ImageConfiguration());
      final completer = Completer<ui.Image>();
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool _) {
          imageStream.removeListener(listener);
          completer.complete(info.image);
        },
        onError: (error, stackTrace) {
          imageStream.removeListener(listener);
          completer.completeError(error, stackTrace);
        },
      );
      imageStream.addListener(listener);

      final image = await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          imageStream.removeListener(listener);
          throw TimeoutException('Image decode timeout');
        },
      );

      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      image.dispose();

      if (byteData == null) {
        return CoverColorResult.defaultResult;
      }

      final rgbaBytes = byteData.buffer.asUint8List();
      final dominantArgb = await compute(_extractDominantColor, rgbaBytes);

      final dominantColor = Color(dominantArgb);
      final luminance = dominantColor.computeLuminance();
      final useDarkText = luminance > 0.5;

      Color lightColor;
      if (useDarkText) {
        lightColor = _blendWithWhite(dominantColor, 0.7);
      } else {
        lightColor = _blendWithWhite(dominantColor, 0.85);
      }

      return CoverColorResult(
        dominantColor: dominantColor,
        lightColor: lightColor,
        useDarkText: useDarkText,
      );
    } catch (e) {
      return CoverColorResult.defaultResult;
    }
  }

  static Future<CoverColorResult> extractFromSong(
    Song song, {
    OnAudioQuery? audioQuery,
  }) async {
    final coverUrl = song.coverUrl;
    if (coverUrl != null && coverUrl.isNotEmpty) {
      if (coverUrl.startsWith('http')) {
        return extract(CachedNetworkImageProvider(coverUrl));
      }
      final file = File(coverUrl);
      if (await file.exists()) {
        return extract(FileImage(file));
      }
      return extract(AssetImage(coverUrl));
    }

    if (song.mediaStoreId != null) {
      final query = audioQuery ?? OnAudioQuery();
      try {
        final Uint8List? bytes = await query.queryArtwork(
          song.mediaStoreId!,
          ArtworkType.AUDIO,
          quality: 100,
          size: 400,
        );
        if (bytes == null || bytes.isEmpty) {
          return CoverColorResult.defaultResult;
        }
        return extract(MemoryImage(bytes));
      } catch (_) {
        return CoverColorResult.defaultResult;
      }
    }

    return CoverColorResult.defaultResult;
  }

  static Color _blendWithWhite(Color color, double factor) {
    return Color.lerp(Colors.white, color, 1 - factor)!;
  }
}

/// CeruMusic-style eager pre-computation: watches current song and
/// computes cover colors in background isolate as soon as the song changes.
/// This runs BEFORE the user opens FullPlayerPage, so colors are cached/ready.
final currentCoverColorProvider = FutureProvider<CoverColorResult?>((
  ref,
) async {
  ref.watch(currentSongIdentityProvider);
  final song = ref.read(playbackControllerProvider).currentSong;
  if (song == null) return null;
  return CoverColorExtractor.extractFromSong(song);
});
