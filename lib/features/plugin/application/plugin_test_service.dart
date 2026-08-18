import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../../player/application/string_similarity.dart';
import '../../player/domain/models/song.dart';
import '../../player/platform/audio_handler.dart';
import '../../settings/domain/models/plugin_info.dart';
import '../data/plugin_host.dart';
import '../data/plugin_service.dart';
import '../domain/plugin_types.dart';
import 'music_source_manager.dart';

/// 单个音质条目的测试状态。
enum PluginTestItemStatus { pending, running, passed, failed }

/// 单个音源的测试阶段。
enum PluginTestSourceStatus { pending, searching, testing, done, failed }

/// 一个音源下某个音质的测试结果。
class PluginTestQualityResult {
  final String quality;
  PluginTestItemStatus status;
  String? note;

  PluginTestQualityResult({required this.quality})
    : status = PluginTestItemStatus.pending,
      note = null;
}

/// 一个音源的测试结果（含该源下所有音质）。
class PluginTestSourceResult {
  final String sourceId;
  final String sourceName;
  final List<PluginTestQualityResult> qualities;

  PluginTestSourceStatus status;
  String? matchText;
  String? searchError;

  PluginTestSourceResult({
    required this.sourceId,
    required this.sourceName,
    required List<String> qualityNames,
  }) : qualities = qualityNames
           .map((name) => PluginTestQualityResult(quality: name))
           .toList(),
       status = PluginTestSourceStatus.pending,
       matchText = null,
       searchError = null;

  int get passedCount =>
      qualities.where((q) => q.status == PluginTestItemStatus.passed).length;

  bool get isAvailable => qualities.isNotEmpty && passedCount > 0;
}

/// 一次插件测试的完整报告。
class PluginTestReport {
  final String pluginName;
  final List<PluginTestSourceResult> sources;

  bool running;
  bool finished;
  bool cancelled;
  String? fatalError;
  PluginTestRuntime? runtime;

  PluginTestReport({required this.pluginName, required this.sources})
    : running = false,
      finished = false,
      cancelled = false,
      fatalError = null,
      runtime = null;

  int get totalQualityCount =>
      sources.fold(0, (sum, s) => sum + s.qualities.length);

  int get passedQualityCount =>
      sources.fold(0, (sum, s) => sum + s.passedCount);

  int get availableSourceCount => sources.where((s) => s.isAvailable).length;
}

/// 音源插件测试服务。
///
/// 采用**严格串行**测试：单个 JS 引擎（`flutter_js` 的 `JavascriptRuntime`
/// 不并发安全，并行调用同一引擎会互相阻塞甚至状态错乱），一次只跑一个
/// 音源、一个音质；每个条目只在真正开始解析时才切换为"测试中"状态，因此
/// 列表里能看到进度逐步推进（已完成的对勾/叉 → 当前转圈 → 未开始的空圈）。
///
/// 测试流程：
/// 1. 优先通过该插件宿主搜索（与启用后实际播放路径一致，保留完整 LX
///    元数据供 musicUrl 解析），按相似度取前几条候选曲目；
/// 2. 对每个音质走与真实播放**完全一致**的解析路径
///    （`getMusicUrlResultCandidates`：kw 源优先内置解析并带提示音/时长
///    过滤，其它源由被测插件解析），逐个候选 URL 探测；
/// 3. 用临时 just_audio 播放器加载链接验证实际可播放（kw 源与真实播放
///    共用同一套时长校验，其它源仅拦截明显试听提示音）；
/// 4. 候选曲目按相似度依次尝试，失败自动重试并递增退避，吸收 CDN 限流、
///    冷启动超时等偶发抖动。
///
/// 未启用的插件通过隔离 JS 引擎测试，不影响全局音源状态。
class PluginTestService {
  final MusicSourceManager _manager;
  final PluginService _pluginService;

  PluginTestService({
    required MusicSourceManager manager,
    required PluginService pluginService,
  }) : _manager = manager,
       _pluginService = pluginService;

  /// 搜索兜底超时（宿主 search 内层为 45s，内置源搜索也由此兜底）。
  static const _searchTimeout = Duration(seconds: 50);

  /// 链接解析超时：放宽以容纳插件冷启动与其内部多接口重试。
  static const _resolveTimeout = Duration(seconds: 60);

  static const _probeTimeout = Duration(seconds: 20);

  /// 失败重试前的等待（逐次递增），缓解 CDN 限流/接口抖动。
  static const _retryDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  static const _maxAttempts = 3;

  /// 匹配候选曲目上限：解析失败时按相似度依次尝试下一首，避免搜索排序
  /// 抖动导致两次测试选中不同歌曲、结果不一致。
  static const _maxMatchCandidates = 3;

  AudioPlayer? _probePlayer;
  final Map<String, List<Song>> _referenceSearchCache = {};

  /// 准备测试报告：加载插件运行时并按宿主声明构建音源×音质骨架。
  ///
  /// 抛出异常表示插件无法加载（文件缺失、代码损坏等）。
  Future<PluginTestReport> prepareReport(PluginInfo plugin) async {
    final runtime = await _pluginService.createTestRuntime(plugin);
    final specs = _manager.getHostSourceSpecs(runtime.host);
    if (specs.isEmpty) {
      if (!runtime.isShared) runtime.dispose();
      throw Exception('插件未声明任何音源，无法测试');
    }
    return PluginTestReport(
      pluginName: plugin.name,
      sources: specs
          .map(
            (spec) => PluginTestSourceResult(
              sourceId: spec.id,
              sourceName: spec.name,
              qualityNames: spec.qualities,
            ),
          )
          .toList(),
    )..runtime = runtime;
  }

  /// 释放报告持有的隔离运行时（共享运行时无操作）。
  void discard(PluginTestReport report) {
    report.runtime?.dispose();
    report.runtime = null;
  }

  /// 执行测试。[report] 必须先经 [prepareReport] 构建并持有运行时。
  ///
  /// 严格串行：逐音源、逐音质执行；每个状态变化后回调 [onChanged]；
  /// [isCancelled] 返回 true 时尽快停止。
  Future<void> runTest({
    required PluginTestReport report,
    required String keyword,
    void Function()? onChanged,
    bool Function()? isCancelled,
  }) async {
    final runtime = report.runtime;
    if (runtime == null) {
      throw Exception('测试报告未初始化，请先调用 prepareReport');
    }

    report.running = true;
    report.finished = false;
    report.cancelled = false;
    report.fatalError = null;
    _referenceSearchCache.clear();
    onChanged?.call();

    final parsed = _parseKeyword(keyword);
    final searchKeyword = parsed.artist.isEmpty
        ? parsed.title
        : '${parsed.title} ${parsed.artist}';

    try {
      for (final source in report.sources) {
        if (_isCancelled(isCancelled)) break;
        await _testSource(
          runtime.host,
          source,
          searchKeyword,
          parsed,
          onChanged: onChanged,
          isCancelled: isCancelled,
        );
      }
    } catch (e) {
      report.fatalError = '测试中断: ${_shortError(e)}';
    } finally {
      if (_isCancelled(isCancelled)) report.cancelled = true;
      report.running = false;
      report.finished = true;
      await _disposeProbePlayer();
      discard(report);
      onChanged?.call();
    }
  }

  Future<void> _testSource(
    PluginHost host,
    PluginTestSourceResult source,
    String searchKeyword,
    ({String title, String artist}) parsed, {
    void Function()? onChanged,
    bool Function()? isCancelled,
  }) async {
    if (_isCancelled(isCancelled)) return;

    _resetSource(source);
    source.status = PluginTestSourceStatus.searching;
    onChanged?.call();

    List<Song> matches = const [];
    var usedReferenceSearch = false;
    try {
      final songs = await _manager
          .searchViaHost(host, searchKeyword, sourceId: source.sourceId)
          .timeout(_searchTimeout);
      matches = _pickBestMatches(
        songs,
        parsed.title,
        parsed.artist,
        sourceId: source.sourceId,
      );
      // Search APIs often return a usable first result with a suffix such as
      // "(Live)" or a differently formatted artist field. The player does
      // not require an exact text match, so do not reject the source solely
      // because the strict similarity threshold missed every result.
      if (matches.isEmpty && songs.isNotEmpty) {
        matches = _pickBestMatches(
          songs,
          parsed.title,
          parsed.artist,
          sourceId: source.sourceId,
          allowLooseMatch: true,
        );
      }
    } on TimeoutException {
      source.searchError = '搜索超时';
    } catch (e) {
      print('[PluginTest] 搜索失败 source=${source.sourceId}: $e');
      source.searchError = '搜索失败';
    }

    // Long-running/resolver-only LX sources may not implement search at all,
    // or may return an envelope that has no exact text match. Use a reliable
    // built-in source only to obtain the test song metadata, then rebase it to
    // the target source and send it through the target plugin's musicUrl
    // resolver. This mirrors real playback, where search and URL resolving
    // are separate capabilities.
    if (matches.isEmpty) {
      matches = await _findReferenceMatches(
        searchKeyword,
        parsed,
        sourceId: source.sourceId,
      );
      usedReferenceSearch = matches.isNotEmpty;
    }

    // 如果当前音源的参考搜索也失败，尝试使用其他可用的内置源作为参考。
    // 某些 LX 插件（如长青、念心等）可能不实现 search，但通过插件宿主
    // 的 searchWithHandler 仍能返回结果。若插件搜索也为空，尝试用 wy 等
    // 稳定内置源获取测试歌曲元数据，然后通过插件的 musicUrl 解析器验证。
    if (matches.isEmpty) {
      const fallbackSources = ['wy', 'kw', 'kg', 'tx', 'mg'];
      for (final fbId in fallbackSources) {
        if (fbId == source.sourceId) continue;
        matches = await _findReferenceMatches(
          searchKeyword,
          parsed,
          sourceId: fbId,
        );
        if (matches.isNotEmpty) {
          usedReferenceSearch = true;
          break;
        }
      }
    }

    if (matches.isEmpty) {
      final reason = source.searchError ?? '未找到匹配曲目';
      source.matchText = reason;
      for (final quality in source.qualities) {
        quality.status = PluginTestItemStatus.failed;
        quality.note = reason;
      }
      source.status = PluginTestSourceStatus.failed;
      onChanged?.call();
      return;
    }

    source.searchError = null;
    source.matchText =
        '${usedReferenceSearch ? '参考：' : ''}'
        '${matches.first.title} - ${matches.first.artist}';
    source.status = PluginTestSourceStatus.testing;
    onChanged?.call();

    for (final quality in source.qualities) {
      if (_isCancelled(isCancelled)) break;
      await _testQuality(
        host,
        quality,
        matches,
        onChanged: onChanged,
        isCancelled: isCancelled,
      );
    }

    source.status = PluginTestSourceStatus.done;
    onChanged?.call();
  }

  Future<void> _testQuality(
    PluginHost host,
    PluginTestQualityResult quality,
    List<Song> matches, {
    void Function()? onChanged,
    bool Function()? isCancelled,
  }) async {
    String? lastNote;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      if (_isCancelled(isCancelled)) return;

      // 仅在真正开始解析时才标记为"测试中"，串行下不会被排队。
      quality.status = PluginTestItemStatus.running;
      quality.note = attempt > 1 ? '重试中…' : null;
      onChanged?.call();

      // 与真实播放完全一致的解析路径：kw 源优先内置解析（含随机账号重试
      // 与提示音/时长过滤），其它源由被测插件解析；候选 URL 逐个探测。
      // 候选曲目按相似度依次尝试，换歌可吸收搜索排序抖动导致的选曲差异。
      for (final match in matches) {
        if (_isCancelled(isCancelled)) return;

        List<PluginMusicUrlResult> candidates = const [];
        try {
          candidates = await _manager
              .getMusicUrlResultCandidates(
                match,
                quality: quality.quality,
                pluginHosts: [host],
              )
              .timeout(_resolveTimeout);
        } on TimeoutException {
          lastNote = '解析超时';
        } catch (e) {
          print(
            '[PluginTest] 解析异常 quality=${quality.quality} '
            'attempt=$attempt: $e',
          );
          lastNote = '解析失败';
        }

        if (candidates.isEmpty) continue;

        for (final candidate in candidates) {
          if (_isCancelled(isCancelled)) return;
          final (ok, note) = await _probePlayable(candidate, match);
          if (ok) {
            quality.status = PluginTestItemStatus.passed;
            quality.note = attempt > 1 ? '重试后通过' : null;
            onChanged?.call();
            return;
          }
          lastNote = note;
        }
      }

      if (attempt < _maxAttempts) {
        await Future.delayed(_retryDelays[attempt - 1]);
      }
    }

    quality.status = PluginTestItemStatus.failed;
    quality.note = lastNote ?? '无法获取播放链接';
    onChanged?.call();
  }

  void _resetSource(PluginTestSourceResult source) {
    source.status = PluginTestSourceStatus.pending;
    source.matchText = null;
    source.searchError = null;
    for (final quality in source.qualities) {
      quality.status = PluginTestItemStatus.pending;
      quality.note = null;
    }
  }

  bool _isCancelled(bool Function()? isCancelled) =>
      isCancelled?.call() ?? false;

  /// 解析"歌名-歌手"格式；无分隔符时整体视为歌名。
  ({String title, String artist}) _parseKeyword(String keyword) {
    final trimmed = keyword.trim();
    final parts = trimmed.split('-');
    if (parts.length < 2) {
      return (title: trimmed, artist: '');
    }
    final artist = parts.last.trim();
    final title = parts.sublist(0, parts.length - 1).join('-').trim();
    if (title.isEmpty || artist.isEmpty) {
      return (title: trimmed, artist: '');
    }
    return (title: title, artist: artist);
  }

  /// 与自动换源一致的歌曲匹配评分：标题 60% + 歌手 40%，阈值 0.5。
  ///
  /// 返回按得分降序的前 [_maxMatchCandidates] 首，解析失败时按顺序换下一
  /// 首尝试；同时强制规范 source，保证后续链接解析走当前音源。
  List<Song> _pickBestMatches(
    List<Song> songs,
    String title,
    String artist, {
    required String sourceId,
    bool allowLooseMatch = false,
  }) {
    final scored = <(double, Song)>[];
    for (final song in songs) {
      final nameScore = strSim(song.title, title);
      final singerScore = artist.isEmpty ? 1.0 : strSim(song.artist, artist);
      final score = nameScore * 0.6 + singerScore * 0.4;
      if (score >= (allowLooseMatch ? 0.15 : 0.4)) {
        scored.add((score, song));
      }
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    final matches = scored
        .take(_maxMatchCandidates)
        .map((entry) => entry.$2.copyWith(source: sourceId))
        .toList();
    if (matches.isNotEmpty || !allowLooseMatch) return matches;

    // A source can legally return a ranked list without title/artist fields
    // that are comparable to the user's query. It is still useful for a
    // connectivity test: probe the ranked candidates and let the audio URL
    // validation decide whether one is playable.
    // 放宽条件：只要歌曲有标题或 ID，都视为可测试候选。
    return songs
        .where((song) => song.title.trim().isNotEmpty || song.id.isNotEmpty)
        .take(_maxMatchCandidates)
        .map((song) => song.copyWith(source: sourceId))
        .toList();
  }

  Future<List<Song>> _findReferenceMatches(
    String searchKeyword,
    ({String title, String artist}) parsed, {
    required String sourceId,
  }) async {
    final cacheKey = '$sourceId:${searchKeyword.trim().toLowerCase()}';
    final cachedSongs = _referenceSearchCache[cacheKey];
    late final List<Song> referenceSongs;
    if (cachedSongs != null) {
      referenceSongs = cachedSongs;
    } else {
      var fetchedSongs = <Song>[];
      try {
        fetchedSongs = await _manager
            .searchBuiltIn(searchKeyword, sourceId: sourceId, limit: 15)
            .timeout(const Duration(seconds: 12));
      } catch (e) {
        print('[PluginTest] 同平台参考搜索失败 source=$sourceId: $e');
      }
      referenceSongs = fetchedSongs;
      _referenceSearchCache[cacheKey] = fetchedSongs;
    }

    final matches = _pickBestMatches(
      referenceSongs,
      parsed.title,
      parsed.artist,
      sourceId: sourceId,
      allowLooseMatch: true,
    );
    return matches;
  }

  /// 用共享播放器加载 URL 验证可播放性。
  ///
  /// 返回 (是否可播放, 失败原因)。kw 源与真实播放共用同一套时长校验
  /// （`kuwoDurationValidationError`），测试通过即实际播放大概率可成功；
  /// 其它源仅拦截"明显是试听提示音"（实际时长 ≤30s 且曲目应有 ≥60s）。
  Future<(bool, String?)> _probePlayable(
    PluginMusicUrlResult resolved,
    Song song,
  ) async {
    final player = _probePlayer ??= AudioPlayer();
    final headers = MusicAudioHandler.audioHeadersForUrl(
      resolved.url,
      songHeaders: resolved.headers,
    );
    try {
      await player
          .setUrl(resolved.url, headers: headers)
          .timeout(_probeTimeout);
    } on TimeoutException {
      return (false, '加载超时');
    } catch (e) {
      return (false, '播放失败: ${_shortError(e)}');
    }

    if (song.source == 'kw') {
      final actual = await _waitForPlayerDuration(
        player,
        const Duration(seconds: 8),
      );
      await _stopProbe(player);
      if (actual == null || actual <= Duration.zero) {
        // 与真实播放一致：URL 已成功加载但时长不可得时按可播放处理
        // （CeruMusic/LX Music 直接播放插件 URL，不做时长校验）。
        return (true, null);
      }
      final error = MusicAudioHandler.kuwoDurationValidationError(song, actual);
      if (error != null) return (false, error);
      return (true, null);
    }

    final duration = player.duration;
    final expected = song.duration;
    if (duration != null &&
        expected >= 60 &&
        duration.inSeconds > 0 &&
        duration.inSeconds <= 30) {
      await _stopProbe(player);
      return (false, '音频仅${duration.inSeconds}秒，疑似试听提示');
    }

    // 停止当前播放以备下一个条目复用，但不释放播放器。
    await _stopProbe(player);
    return (true, null);
  }

  /// 等待播放器给出有效时长（与真实播放的 kw 时长校验一致）。
  Future<Duration?> _waitForPlayerDuration(
    AudioPlayer player,
    Duration timeout,
  ) async {
    var duration = player.duration;
    if (duration != null && duration > Duration.zero) return duration;
    try {
      return await player.durationStream
          .firstWhere((d) => d != null && d > Duration.zero)
          .timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  Future<void> _stopProbe(AudioPlayer player) async {
    try {
      await player.stop();
    } catch (_) {}
  }

  Future<void> _disposeProbePlayer() async {
    final player = _probePlayer;
    _probePlayer = null;
    if (player == null) return;
    try {
      await player.dispose();
    } catch (_) {}
  }

  static String _shortError(Object e) {
    var text = e.toString().replaceFirst('Exception: ', '').trim();
    if (text.length > 40) {
      text = '${text.substring(0, 40)}…';
    }
    return text.isEmpty ? '未知错误' : text;
  }
}
