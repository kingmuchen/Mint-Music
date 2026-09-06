import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../player/domain/models/song.dart';
import '../../../plugin/application/music_source_manager.dart';

/// 本地歌曲元数据自动获取器。
///
/// 当本地歌曲缺少封面或歌词时，自动从五大音源搜索匹配，
/// 将封面 URL 和歌词保存到 Song 字段。
class LocalMetadataFetcher {
  LocalMetadataFetcher(this._musicSourceManager);

  final MusicSourceManager _musicSourceManager;

  /// 已经确认无法获取元数据的歌曲 ID 集合（搜索无结果或全部失败），避免反复重试。
  final Set<String> _confirmedMissing = {};

  /// 检查歌曲是否需要自动获取元数据。
  bool needsFetch(Song song) {
    if (!song.isLocal) return false;
    if (_confirmedMissing.contains(song.id)) return false;
    final needsCover = !_hasValidCover(song);
    final needsLyrics = song.lrc == null || song.lrc!.isEmpty;
    return needsCover || needsLyrics;
  }

  /// 判断歌曲是否已有有效封面。
  /// 只看 coverUrl 是否实际指向一个可用的文件/URL。
  /// hasCover 和 mediaStoreId 不能作为判断依据（扫描时 hasCover 始终为 true，
  /// mediaStoreId 始终非空，但 MediaStore 不一定有 artwork）。
  bool _hasValidCover(Song song) {
    return song.coverUrl != null && song.coverUrl!.isNotEmpty;
  }

  /// 自动获取歌曲的封面和歌词。
  ///
  /// 返回更新后的 Song（如果找到更好的匹配），否则返回原 Song。
  Future<Song> fetch(Song song) async {
    final needsCover = !_hasValidCover(song);
    final needsLyrics = song.lrc == null || song.lrc!.isEmpty;

    if (!needsCover && !needsLyrics) return song;

    debugPrint(
      '[LocalMetadataFetcher] 开始自动获取: ${song.title} - ${song.artist} '
      '(needsCover=$needsCover, needsLyrics=$needsLyrics)',
    );

    try {
      final searchQuery = _buildSearchQuery(song);
      final aggregated = await _musicSourceManager.aggregateSearch(
        searchQuery,
        sourceIds: const ['wy', 'kg', 'tx', 'kw', 'mg'],
        limit: 5,
      );

      if (aggregated.isEmpty) {
        debugPrint('[LocalMetadataFetcher] 搜索无结果: ${song.title}');
        _confirmedMissing.add(song.id);
        return song;
      }

      // 收集所有候选结果
      final candidates = <_Candidate>[];
      for (final entry in aggregated.entries) {
        final sourceId = entry.key;
        for (final searchSong in entry.value) {
          candidates.add(_Candidate(
            song: searchSong.copyWith(source: sourceId),
            sourceId: sourceId,
          ));
        }
      }

      if (candidates.isEmpty) return song;

      // 评分并排序
      candidates.sort((a, b) =>
          _scoreCandidate(b, song).compareTo(_scoreCandidate(a, song)));

      // 过滤掉低分候选
      final goodCandidates = candidates
          .where((c) => _scoreCandidate(c, song) >= 0.3)
          .toList();

      if (goodCandidates.isEmpty) {
        debugPrint('[LocalMetadataFetcher] 无合适匹配: ${song.title}');
        _confirmedMissing.add(song.id);
        return song;
      }

      // 并发获取：同时获取封面和歌词
      String? bestLyric;
      _Candidate? bestLyricCandidate;
      String? bestCoverUrl;
      _Candidate? bestCoverCandidate;

      if (needsLyrics) {
        // 并发从多个候选获取歌词，取最先成功的高分结果
        bestLyric = await _fetchLyricsConcurrent(
          goodCandidates,
          song,
          onFound: (lyric, candidate) {
            bestLyricCandidate = candidate;
          },
        );
      }

      if (needsCover) {
        // 从最优候选获取封面
        for (final candidate in goodCandidates) {
          final coverUrl = await _fetchCoverUrl(candidate);
          if (coverUrl != null && coverUrl.isNotEmpty) {
            bestCoverUrl = coverUrl;
            bestCoverCandidate = candidate;
            break;
          }
        }
      }

      if (bestLyric == null && bestCoverUrl == null) {
        debugPrint('[LocalMetadataFetcher] 未找到匹配: ${song.title}');
        _confirmedMissing.add(song.id);
        return song;
      }

      // 组装结果
      final matchCandidate = bestCoverCandidate ?? bestLyricCandidate!;
      debugPrint(
        '[LocalMetadataFetcher] 匹配成功: ${song.title} '
        '← ${matchCandidate.sourceId}/${matchCandidate.song.title} '
        '(lyric=${bestLyric != null}, cover=${bestCoverUrl != null})',
      );

      return _applyResults(
        song,
        matchCandidate,
        bestCoverUrl,
        bestLyric,
      );
    } catch (e) {
      debugPrint('[LocalMetadataFetcher] 自动获取失败: ${song.title} - $e');
      _confirmedMissing.add(song.id);
      return song;
    }
  }

  /// 并发从多个候选获取歌词，返回最优结果。
  ///
  /// 对高分候选并行发起歌词请求，最先返回的有效歌词即为结果。
  Future<String?> _fetchLyricsConcurrent(
    List<_Candidate> candidates,
    Song local, {
    void Function(String lyric, _Candidate candidate)? onFound,
  }) async {
    // 取前 5 个候选并发请求
    final topCandidates = candidates.take(5).toList();
    final completer = Completer<String?>();
    var settled = false;

    for (final candidate in topCandidates) {
      unawaited(() async {
        try {
          final lyric = await _fetchLyricText(candidate);
          if (!settled && lyric != null && lyric.isNotEmpty) {
            settled = true;
            onFound?.call(lyric, candidate);
            if (!completer.isCompleted) completer.complete(lyric);
          }
        } catch (_) {}
        // 所有请求完成后，如果还没有结果，返回 null
        if (!settled && !_hasPendingRequests(topCandidates, candidate)) {
          if (!completer.isCompleted) completer.complete(null);
        }
      }());
    }

    // 兜底超时
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        settled = true;
        return null;
      },
    );
  }

  /// 检查是否还有未完成的请求（简单的近似判断）。
  bool _hasPendingRequests(List<_Candidate> all, _Candidate current) {
    // 无法精确判断，直接返回 true 让 completer 等待
    return false;
  }

  /// 构建搜索关键词：优先使用标题，如果标题质量差则拼接艺术家。
  String _buildSearchQuery(Song song) {
    final title = song.title.trim();
    final artist = song.artist.trim();

    if (title.isEmpty || title == '未知曲目') {
      return artist.isNotEmpty && artist != '未知艺术家' ? artist : '';
    }

    if (artist.isEmpty || artist == '未知艺术家') return title;

    return '$title $artist';
  }

  /// 评分候选结果。返回 0.0 ~ 1.0 的分数。
  double _scoreCandidate(_Candidate candidate, Song local) {
    double score = 0.0;
    final cs = candidate.song;

    // 标题匹配 (权重 0.5)
    final titleScore = _stringSimilarity(
      cs.title.toLowerCase(),
      local.title.toLowerCase(),
    );
    score += titleScore * 0.5;

    // 艺术家匹配 (权重 0.3)
    final artistScore = _stringSimilarity(
      cs.artist.toLowerCase(),
      local.artist.toLowerCase(),
    );
    score += artistScore * 0.3;

    // 时长匹配 (权重 0.1)
    if (local.duration > 0 && cs.duration > 0) {
      final durationDiff = (cs.duration - local.duration).abs();
      final durationScore = durationDiff <= 3
          ? 1.0
          : durationDiff <= 10
              ? 0.7
              : durationDiff <= 30
                  ? 0.3
                  : 0.0;
      score += durationScore * 0.1;
    }

    // 封面可用性 (权重 0.05)
    if (cs.coverUrl != null && cs.coverUrl!.isNotEmpty) {
      score += 0.05;
    }

    // 歌词可用性 (权重 0.05)
    score += 0.05;

    return score;
  }

  /// 字符串相似度：基于字符级 Jaccard 相似度。
  double _stringSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    if (a == b) return 1.0;
    if (a.contains(b) || b.contains(a)) return 0.8;

    final setA = a.split('').toSet();
    final setB = b.split('').toSet();
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    return union > 0 ? intersection / union : 0.0;
  }

  /// 从候选源获取封面 URL。
  Future<String?> _fetchCoverUrl(_Candidate candidate) async {
    try {
      return await _musicSourceManager.getPic(
        candidate.song,
        preferBuiltIn: false,
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  /// 从候选源获取歌词文本。
  Future<String?> _fetchLyricText(_Candidate candidate) async {
    try {
      final result = await _musicSourceManager
          .getLyricResult(candidate.song)
          .timeout(const Duration(seconds: 8));
      if (result == null) return null;
      if (result.crlyric != null && result.crlyric!.isNotEmpty) {
        return result.crlyric;
      }
      if (result.lrc != null && result.lrc!.isNotEmpty) {
        return result.lrc;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 将获取结果应用到本地歌曲。
  Future<Song> _applyResults(
    Song local,
    _Candidate candidate,
    String? coverUrl,
    String? lyric,
  ) async {
    // 直接使用网络 URL 作为 coverUrl（与精准匹配行为一致）。
    // MusicCoverImage 内部通过 Dio + 内存缓存加载网络图片，
    // 如果存为本地文件路径，MusicCoverImage 无法识别。
    return local.copyWith(
      title: candidate.song.title.isNotEmpty ? candidate.song.title : local.title,
      artist: candidate.song.artist.isNotEmpty ? candidate.song.artist : local.artist,
      album: candidate.song.album.isNotEmpty ? candidate.song.album : local.album,
      coverUrl: coverUrl ?? local.coverUrl,
      hasCover: (coverUrl != null && coverUrl.isNotEmpty) || local.hasCover,
      lrc: lyric ?? local.lrc,
    );
  }
}

class _Candidate {
  final Song song;
  final String sourceId;

  const _Candidate({required this.song, required this.sourceId});
}
