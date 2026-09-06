import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/l10n/l10n.dart';
import '../../features/player/domain/models/song.dart';
import '../../features/library/domain/models/playlist.dart';

enum PosterTemplate { classic, minimal, polaroid }

class SharePosterGenerator {
  SharePosterGenerator._();

  static const double _width = 720;
  static const double _height = 1100;

  static Future<Uint8List?> generateSongPoster({
    required Song song,
    Uint8List? coverBytes,
    PosterTemplate template = PosterTemplate.classic,
    String? qrContent,
  }) async {
    final coverImage = coverBytes != null ? await _decodeImage(coverBytes) : null;
    final qr = qrContent ?? '【薄荷音乐】${song.title} - ${song.artist}';

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, _width, _height));

    switch (template) {
      case PosterTemplate.classic:
        _drawClassicPoster(
          canvas: canvas,
          coverImage: coverImage,
          title: song.title,
          subtitle: song.artist.isNotEmpty ? song.artist : (song.album.isNotEmpty ? song.album : ''),
          qrContent: qr,
        );
      case PosterTemplate.minimal:
        _drawMinimalPoster(
          canvas: canvas,
          coverImage: coverImage,
          title: song.title,
          subtitle: song.artist.isNotEmpty ? song.artist : '',
          qrContent: qr,
        );
      case PosterTemplate.polaroid:
        _drawPolaroidPoster(
          canvas: canvas,
          coverImage: coverImage,
          title: song.title,
          subtitle: song.artist.isNotEmpty ? song.artist : '',
          qrContent: qr,
        );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(_width.toInt(), _height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  static Future<Uint8List?> generatePlaylistPoster({
    required Playlist playlist,
    Uint8List? coverBytes,
    PosterTemplate template = PosterTemplate.classic,
    String? qrContent,
  }) async {
    ui.Image? coverImage;
    if (coverBytes != null) {
      coverImage = await _decodeImage(coverBytes);
    }

    final qr = qrContent ?? '【薄荷音乐】${tr('分享歌单')}：${playlist.name}';

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, _width, _height));

    switch (template) {
      case PosterTemplate.classic:
        _drawClassicPoster(
          canvas: canvas,
          coverImage: coverImage,
          title: playlist.name,
          subtitle: tr('${playlist.songCount} 首歌曲'),
          qrContent: qr,
        );
      case PosterTemplate.minimal:
        _drawMinimalPoster(
          canvas: canvas,
          coverImage: coverImage,
          title: playlist.name,
          subtitle: tr('${playlist.songCount} 首歌曲'),
          qrContent: qr,
        );
      case PosterTemplate.polaroid:
        _drawPolaroidPoster(
          canvas: canvas,
          coverImage: coverImage,
          title: playlist.name,
          subtitle: tr('${playlist.songCount} 首歌曲'),
          qrContent: qr,
        );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(_width.toInt(), _height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  static Future<ui.Image?> _decodeImage(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 360,
        targetHeight: 360,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  static void _drawClassicPoster({
    required Canvas canvas,
    required ui.Image? coverImage,
    required String title,
    required String subtitle,
    required String qrContent,
  }) {
    final bgGradient = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1A0533), Color(0xFF0D0D2B), Color(0xFF1A0533)],
      ).createShader(Rect.fromLTWH(0, 0, _width, _height));
    canvas.drawRect(Rect.fromLTWH(0, 0, _width, _height), bgGradient);

    final accentPaint = Paint()..color = const Color(0x187D7AFF);
    canvas.drawCircle(const Offset(100, 200), 300, accentPaint);
    canvas.drawCircle(const Offset(620, 800), 250, accentPaint);

    if (coverImage != null) {
      final coverSize = 320.0;
      final coverLeft = (_width - coverSize) / 2;
      final coverTop = 140.0;
      final coverRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(coverLeft, coverTop, coverSize, coverSize),
        const Radius.circular(24),
      );
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
      canvas.drawRRect(
        coverRect.shift(const Offset(0, 8)),
        shadowPaint,
      );
      canvas.save();
      canvas.clipRRect(coverRect);
      canvas.drawImageRect(
        coverImage,
        Rect.fromLTWH(0, 0, coverImage.width.toDouble(), coverImage.height.toDouble()),
        Rect.fromLTWH(coverLeft, coverTop, coverSize, coverSize),
        Paint(),
      );
      canvas.restore();
    }

    final titleStyle = TextStyle(
      color: Colors.white,
      fontSize: 32,
      fontWeight: FontWeight.bold,
    );
    final subtitleStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.6),
      fontSize: 22,
    );

    final titlePainter = TextPainter(
      text: TextSpan(text: title, style: titleStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    );
    titlePainter.layout(maxWidth: _width - 80);
    titlePainter.paint(canvas, Offset((_width - titlePainter.width) / 2, coverImage != null ? 500 : 200));

    final subY = titlePainter.height + (coverImage != null ? 510 : 210);
    final subPainter = TextPainter(
      text: TextSpan(text: subtitle, style: subtitleStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    );
    subPainter.layout(maxWidth: _width - 80);
    subPainter.paint(canvas, Offset((_width - subPainter.width) / 2, subY));

    _drawQrCode(canvas, qrContent, 160, subY + 80);

    final brandStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.3),
      fontSize: 14,
      letterSpacing: 4,
    );
    _drawCenteredText(canvas, '薄荷音乐', brandStyle, _height - 50);
  }

  static void _drawMinimalPoster({
    required Canvas canvas,
    required ui.Image? coverImage,
    required String title,
    required String subtitle,
    required String qrContent,
  }) {
    final bgPaint = Paint()..color = const Color(0xFF1E1E2E);
    canvas.drawRect(Rect.fromLTWH(0, 0, _width, _height), bgPaint);

    final cardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(40, 80, _width - 80, _height - 160),
      const Radius.circular(32),
    );
    final cardPaint = Paint()
      ..color = const Color(0xFF2A2A3E)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(cardRect.shift(const Offset(0, 4)), cardPaint);
    canvas.drawRRect(cardRect, Paint()..color = const Color(0xFF2A2A3E));

    if (coverImage != null) {
      final coverSize = 260.0;
      final coverLeft = (_width - coverSize) / 2;
      final coverTop = 140.0;
      final coverRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(coverLeft, coverTop, coverSize, coverSize),
        const Radius.circular(20),
      );
      canvas.save();
      canvas.clipRRect(coverRect);
      canvas.drawImageRect(
        coverImage,
        Rect.fromLTWH(0, 0, coverImage.width.toDouble(), coverImage.height.toDouble()),
        Rect.fromLTWH(coverLeft, coverTop, coverSize, coverSize),
        Paint(),
      );
      canvas.restore();
    }

    final titleStyle = TextStyle(
      color: Colors.white,
      fontSize: 30,
      fontWeight: FontWeight.w600,
    );
    final subStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.5),
      fontSize: 20,
    );

    final titlePainter = TextPainter(
      text: TextSpan(text: title, style: titleStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    );
    titlePainter.layout(maxWidth: _width - 120);
    titlePainter.paint(canvas, Offset((_width - titlePainter.width) / 2, coverImage != null ? 440 : 200));

    final subY = titlePainter.height + (coverImage != null ? 450 : 210);
    _drawCenteredText(canvas, subtitle, subStyle, subY);

    _drawQrCode(canvas, qrContent, 160, subY + 100);

    _drawCenteredText(
      canvas,
      '薄荷音乐',
      TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 13, letterSpacing: 3),
      _height - 50,
    );
  }

  static void _drawPolaroidPoster({
    required Canvas canvas,
    required ui.Image? coverImage,
    required String title,
    required String subtitle,
    required String qrContent,
  }) {
    final bgPaint = Paint()..color = const Color(0xFFF5F0EB);
    canvas.drawRect(Rect.fromLTWH(0, 0, _width, _height), bgPaint);

    final cardLeft = 80.0;
    final cardTop = 80.0;
    final cardWidth = _width - 160;
    final cardHeight = _height - 180;
    final cardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cardLeft, cardTop, cardWidth, cardHeight),
      const Radius.circular(8),
    );
    canvas.drawRRect(cardRect, Paint()..color = Colors.white);

    final shadowPaint = Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawRRect(cardRect.shift(const Offset(2, 6)), shadowPaint);
    canvas.drawRRect(cardRect, Paint()..color = Colors.white);

    if (coverImage != null) {
      final coverSize = cardWidth - 40;
      final coverLeft = cardLeft + 20;
      final coverTop2 = cardTop + 20;
      final coverRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(coverLeft, coverTop2, coverSize, coverSize),
        const Radius.circular(4),
      );
      canvas.save();
      canvas.clipRRect(coverRect);
      canvas.drawImageRect(
        coverImage,
        Rect.fromLTWH(0, 0, coverImage.width.toDouble(), coverImage.height.toDouble()),
        Rect.fromLTWH(coverLeft, coverTop2, coverSize, coverSize),
        Paint(),
      );
      canvas.restore();
    }

    final textStartY = (cardTop + 20 + (coverImage != null ? cardWidth - 40 : 0) + 24);
    final titleStyle = TextStyle(
      color: const Color(0xFF2D2D3A),
      fontSize: 26,
      fontWeight: FontWeight.bold,
    );
    final titlePainter = TextPainter(
      text: TextSpan(text: title, style: titleStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    );
    titlePainter.layout(maxWidth: cardWidth - 40);
    titlePainter.paint(canvas, Offset((_width - titlePainter.width) / 2, textStartY));

    final subStyle = TextStyle(
      color: const Color(0xFF888899),
      fontSize: 18,
    );
    _drawCenteredText(canvas, subtitle, subStyle, textStartY + 40);

    _drawQrCode(canvas, qrContent, 100, textStartY + 80,
      qrColor: const Color(0xFF2D2D3A),
    );

    _drawCenteredText(
      canvas,
      '薄荷音乐',
      TextStyle(color: const Color(0xFFBBBBCC), fontSize: 12, letterSpacing: 3),
      cardTop + cardHeight + 30,
    );
  }

  static void _drawQrCode(
    Canvas canvas,
    String data,
    double size,
    double top, {
    Color qrColor = Colors.white,
  }) {
    final qrCode = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final qrImage = QrImage(qrCode);
    final moduleCount = qrImage.moduleCount;
    final cellSize = size / moduleCount;
    final left = (_width - size) / 2;
    final paint = Paint()..color = qrColor;

    canvas.save();
    canvas.translate(left, top);
    for (int row = 0; row < moduleCount; row++) {
      for (int col = 0; col < moduleCount; col++) {
        if (qrImage.isDark(row, col)) {
          canvas.drawRect(
            Rect.fromLTWH(col * cellSize, row * cellSize, cellSize, cellSize),
            paint,
          );
        }
      }
    }
    canvas.restore();
  }

  static void _drawCenteredText(Canvas canvas, String text, TextStyle style, double y) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(canvas, Offset((_width - painter.width) / 2, y));
  }
}
