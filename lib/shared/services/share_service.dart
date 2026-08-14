import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../features/player/domain/models/song.dart';
import '../../features/library/domain/models/playlist.dart';
import 'share_poster_generator.dart';

class ShareService {
  ShareService._();

  static Future<void> shareSong(
    Song song, {
    Uint8List? coverBytes,
    PosterTemplate template = PosterTemplate.classic,
  }) async {
    final text = _buildSongText(song);
    final qrContent = shareQrContent(song);

    Uint8List? bytes = coverBytes;
    if (bytes == null && song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      bytes = await downloadCover(song.coverUrl!);
    }

    if (bytes != null) {
      final poster = await SharePosterGenerator.generateSongPoster(
        song: song,
        coverBytes: bytes,
        template: template,
        qrContent: qrContent,
      );
      if (poster != null) {
        await _shareWithCover(text, poster, '${song.id}_poster.png');
        return;
      }
      await _shareWithCover(text, bytes, '${song.id}.jpg');
      return;
    }

    await Share.share(text);
  }

  static Future<void> sharePlaylist(
    Playlist playlist, {
    PosterTemplate template = PosterTemplate.classic,
  }) async {
    final text = '【薄荷音乐】分享歌单：${playlist.name}';

    Uint8List? coverBytes;
    if (playlist.coverImgUrl.isNotEmpty) {
      coverBytes = await downloadCover(playlist.coverImgUrl);
    }

    final poster = await SharePosterGenerator.generatePlaylistPoster(
      playlist: playlist,
      coverBytes: coverBytes,
      template: template,
    );

    if (poster != null) {
      await _shareWithCover(text, poster, 'playlist_${playlist.id}_poster.png');
      return;
    }

    if (coverBytes != null) {
      await _shareWithCover(text, coverBytes, 'playlist_${playlist.id}.jpg');
      return;
    }

    final json = playlist.toJson();
    final content = jsonEncode(json);
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/playlist_${playlist.id.replaceAll(RegExp(r'[^\w]'), '_')}.json',
    );
    await file.writeAsString(content);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: text,
    );
  }

  static Future<void> shareText(String text) async {
    await Share.share(text);
  }

  static String? buildPlayUrl(Song song) {
    if (song.source == null) return null;
    String id;
    switch (song.source) {
      case 'wy':
        id = song.id.startsWith('wy_') ? song.id.substring(3) : song.id;
        return 'https://music.163.com/#/song?id=$id';
      case 'tx':
        id = song.id.startsWith('tx_') ? song.id.substring(3) : song.id;
        return 'https://y.qq.com/n/ryqq/songDetail/$id';
      case 'kg':
        id = song.id.startsWith('kg_') ? song.id.substring(3) : song.id;
        return 'https://www.kugou.com/song/#hash=$id';
      case 'kw': {
        if (song.id.startsWith('kw_')) {
          id = song.id.substring(3);
          // kw_digest-{d}__{rid} → extract part after __
          final doubleUnderscore = id.indexOf('__');
          if (doubleUnderscore != -1) {
            id = id.substring(doubleUnderscore + 2);
          }
        } else {
          id = song.id;
        }
        return 'https://www.kuwo.cn/play_detail/$id';
      }
      case 'mg':
        id = song.id.startsWith('mg_') ? song.id.substring(3) : song.id;
        return 'https://music.migu.cn/v3/music/song/$id';
      default:
        return null;
    }
  }

  static String _buildSongText(Song song) {
    final buffer = StringBuffer();
    buffer.write('【薄荷音乐】');
    buffer.write(song.title);
    if (song.artist.isNotEmpty) {
      buffer.write(' - ${song.artist}');
    }
    if (song.album.isNotEmpty) {
      buffer.write(' （《${song.album}》）');
    }
    final url = buildPlayUrl(song);
    if (url != null) {
      buffer.write('\n$url');
    }
    return buffer.toString();
  }

  static String shareQrContent(Song song) {
    final buffer = StringBuffer();
    buffer.write('【薄荷音乐】${song.title}');
    if (song.artist.isNotEmpty) {
      buffer.write(' - ${song.artist}');
    }
    final url = buildPlayUrl(song);
    if (url != null) {
      buffer.write('\n$url');
    }
    return buffer.toString();
  }

  static Future<Uint8List?> downloadCover(String url) async {
    try {
      final needsReferer = url.contains('music.126.net');
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ));
      if (needsReferer) {
        dio.options.headers['Referer'] = 'https://music.163.com';
        dio.options.headers['User-Agent'] =
            'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36';
      }
      final response = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.data != null && response.data!.isNotEmpty) {
        return Uint8List.fromList(response.data!);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _shareWithCover(
    String text,
    Uint8List bytes,
    String filename,
  ) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$filename');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: text);
    } catch (_) {
      await Share.share(text);
    }
  }
}
