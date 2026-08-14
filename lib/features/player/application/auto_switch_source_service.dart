import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/models/song.dart';
import '../../plugin/application/music_source_manager.dart';
import 'string_similarity.dart';

/// 自动换源服务 — 照搬 CeruMusic `audioHelpers.ts` 逻辑
///
/// CeruMusic 的自动换源策略：
/// 1. getCandidateSongs: 在所有候选音源中搜索与当前歌曲匹配的歌曲，
///    按标题相似度(60%) + 歌手相似度(40%) + 时长匹配度排序
/// 2. tryAutoSwitch/autoSwitchSource: 遍历候选列表，逐个尝试获取播放 URL，
///    返回第一个可用的
class AutoSwitchSourceService {
  final MusicSourceManager _musicSourceManager;
  final void Function(String message, {Color? backgroundColor}) _showMessage;

  static const List<String> _fallbackSources = ['wy', 'tx', 'kg', 'kw', 'mg'];

  AutoSwitchSourceService({
    required MusicSourceManager musicSourceManager,
    required void Function(String message, {Color? backgroundColor})
    showMessage,
  }) : _musicSourceManager = musicSourceManager,
       _showMessage = showMessage;

  /// 照搬 CeruMusic getCandidateSongs
  ///
  /// - [originalSong]: 需要换源的歌曲
  /// - [activeSourceIds]: 用户配置的音源 ID 列表（来自 sourceQualityMap 的 keys）
  ///   如果为空/null，使用默认全部音源
  ///
  /// 返回按匹配度排序的候选歌曲列表
  Future<List<Song>> getCandidateSongs(
    Song originalSong, {
    List<String>? activeSourceIds,
  }) async {
    _showMessage('当前源播放失败，正在尝试自动换源...');

    var sources = activeSourceIds != null && activeSourceIds.isNotEmpty
        ? List<String>.from(activeSourceIds)
        : List<String>.from(_fallbackSources);

    // CeruMusic: 移除当前源
    sources = sources.where((s) => s != originalSong.source).toList();

    if (sources.isEmpty) {
      throw Exception('没有其他可用的音源');
    }

    // CeruMusic: searchKeyword = `${originalSong.name} ${originalSong.singer}`
    final searchKeyword = '${originalSong.title} ${originalSong.artist}'.trim();
    final originalDuration = originalSong.duration;

    final searchPromises = sources.map((source) async {
      try {
        final songs = await _musicSourceManager.search(
          searchKeyword,
          sourceId: source,
          page: 1,
          limit: 15,
        );
        return songs.map((s) => s.copyWith(source: source)).toList();
      } catch (e) {
        debugPrint('[AutoSwitchSource] Search $source failed: $e');
        return <Song>[];
      }
    });

    final results = (await Future.wait(
      searchPromises,
    )).expand((list) => list).toList();

    // CeruMusic 评分逻辑：
    //   score = nameScore * 0.6 + singerScore * 0.4
    //   duration diff <= 5s → +0.2, diff > 40s → -0.3
    //   filter: score > 0.6
    final ranked =
        results
            .map((item) {
              final nameScore = strSim(item.title, originalSong.title);
              final singerScore = strSim(item.artist, originalSong.artist);
              var score = nameScore * 0.6 + singerScore * 0.4;

              if (originalDuration > 0 && item.duration > 0) {
                final diff = (originalDuration - item.duration).abs();
                if (diff <= 5) {
                  score += 0.2;
                } else if (diff > 40) {
                  score -= 0.3;
                }
              }

              return _ScoredSong(item, score);
            })
            .where((x) => x.score > 0.6)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));

    if (ranked.isEmpty) {
      throw Exception('未找到其他源的匹配歌曲');
    }

    debugPrint(
      '[AutoSwitchSource] Found ${ranked.length} candidates from ${sources.length} sources',
    );
    return ranked.map((r) => r.song).toList();
  }

  /// 照搬 CeruMusic autoSwitchSource
  ///
  /// 遍历候选列表，对每个候选尝试获取播放 URL，返回第一个可用 URL 的 Song。
  /// 如果全部失败，返回 null。
  ///
  /// 注意：此方法仅通过 getMusicUrl 验证 URL 字符串非空，不验证实际可播放性。
  /// 调用方应在成功获取 URL 后实际播放验证，确认播放成功后再显示切换提示。
  Future<Song?> tryAutoSwitch(
    Song originalSong, {
    List<String>? activeSourceIds,
  }) async {
    try {
      final candidates = await getCandidateSongs(
        originalSong,
        activeSourceIds: activeSourceIds,
      );

      for (final item in candidates) {
        try {
          final urls = await _musicSourceManager.getMusicUrlCandidates(item);
          for (final url in urls) {
            if (url.isNotEmpty) {
              return item.copyWith(sourceUrl: url);
            }
          }
        } catch (e) {
          debugPrint('[AutoSwitchSource] Source ${item.source} URL failed: $e');
          continue;
        }
      }

      _showMessage('所有可用源都无法播放');
      return null;
    } on Exception catch (e) {
      _showMessage('$e');
      return null;
    }
  }
}

class _ScoredSong {
  final Song song;
  final double score;
  const _ScoredSong(this.song, this.score);
}
