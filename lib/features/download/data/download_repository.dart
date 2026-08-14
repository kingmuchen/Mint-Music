import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/platform/media_scanner.dart';
import '../../../core/platform/permission_helper.dart';
import '../domain/models/download_task.dart';
import '../domain/services/tag_write_service.dart';
import '../../player/domain/models/song.dart';

typedef UrlFetcher = Future<String?> Function(DownloadTask task);
typedef TagWriteOptionsFetcher = TagWriteOptions Function();
typedef LyricFetcher = Future<String?> Function(Song song);
typedef QualityValidator = List<String> Function(String sourceId);

class TagWriteOptions {
  final bool basicInfo;
  final bool cover;
  final bool lyrics;
  final bool downloadLyrics;
  final String lyricFormat;

  const TagWriteOptions({
    this.basicInfo = true,
    this.cover = true,
    this.lyrics = true,
    this.downloadLyrics = false,
    this.lyricFormat = 'word-by-word',
  });
}

class DownloadRepository {
  static const _tasksKey = 'download_tasks';
  static const _maxRetries = 3;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 10),
  ));
  final List<DownloadTask> _tasks = [];
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, DateTime> _lastProgressTime = {};
  final Map<String, int> _lastProgressBytes = {};
  final StreamController<List<DownloadTask>> _taskController =
      StreamController<List<DownloadTask>>.broadcast();

  int _maxConcurrent = 3;
  int _activeDownloads = 0;
  final Set<String> _initializingTasks = {};
  final Map<String, bool> _fileLocks = {};
  bool _initialized = false;
  String _downloadDir = '/storage/emulated/0/Music/MintMusic';
  bool _wifiOnly = true;
  UrlFetcher? _urlFetcher;
  void Function(String dirPath)? onDirectoryChanged;
  final TagWriteService _tagWriteService = TagWriteService();
  TagWriteOptionsFetcher? _tagWriteOptionsFetcher;
  LyricFetcher? _lyricFetcher;
  QualityValidator? _qualityValidator;

  void Function(DownloadTask task, {Color? backgroundColor})? onTaskStarted;
  void Function(DownloadTask task, {Color? backgroundColor})? onTaskCompleted;
  void Function(DownloadTask task, String error, {Color? backgroundColor})? onTaskError;

  Stream<List<DownloadTask>> get taskStream async* {
    yield List.unmodifiable(_tasks);
    yield* _taskController.stream;
  }
  int get maxConcurrent => _maxConcurrent;
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  void setUrlFetcher(UrlFetcher fetcher) => _urlFetcher = fetcher;
  void setTagWriteOptionsFetcher(TagWriteOptionsFetcher fetcher) => _tagWriteOptionsFetcher = fetcher;
  void setLyricFetcher(LyricFetcher fetcher) => _lyricFetcher = fetcher;
  void setQualityValidator(QualityValidator validator) => _qualityValidator = validator;

  Future<void> init({String? downloadDir, bool? wifiOnly, int? maxConcurrent}) async {
    if (_initialized) return;
    _initialized = true;

    if (downloadDir != null && downloadDir.isNotEmpty) {
      _downloadDir = downloadDir;
    }
    onDirectoryChanged?.call(_downloadDir);
    if (wifiOnly != null) _wifiOnly = wifiOnly;
    if (maxConcurrent != null) _maxConcurrent = maxConcurrent;

    final prefs = await SharedPreferences.getInstance();
    final tasksJson = prefs.getString(_tasksKey);
    if (tasksJson != null) {
      try {
        final list = jsonDecode(tasksJson) as List;
        for (final t in list) {
          final task = DownloadTask.fromJson(t);
          // 恢复时，下载中的任务变为暂停
          if (task.status == DownloadStatus.downloading) {
            _tasks.add(task.copyWith(status: DownloadStatus.paused));
          } else if (task.status == DownloadStatus.queued) {
            _tasks.add(task);
          } else {
            _tasks.add(task);
          }
        }
      } catch (e) {
        debugPrint('[DownloadRepository] 加载任务失败: $e');
      }
    }

    // 验证已完成任务的文件是否存在
    for (int i = 0; i < _tasks.length; i++) {
      if (_tasks[i].status == DownloadStatus.completed) {
        final file = File(_tasks[i].filePath);
        if (!await file.exists()) {
          _tasks[i] = _tasks[i].copyWith(
            status: DownloadStatus.error,
            error: '文件已删除或移动',
          );
        }
      }
    }

    _emitUpdate();
    _processQueue();
  }

  void updateSettings({String? downloadDir, bool? wifiOnly, int? maxConcurrent}) {
    if (downloadDir != null) {
      _downloadDir = downloadDir;
      onDirectoryChanged?.call(_downloadDir);
    }
    if (wifiOnly != null) _wifiOnly = wifiOnly;
    if (maxConcurrent != null) {
      _maxConcurrent = maxConcurrent;
      _processQueue();
    }
  }

  // ==================== 核心操作 ====================

  /// 检查存储权限。公共目录需要 MANAGE_EXTERNAL_STORAGE。
  Future<bool> _ensureStoragePermission() async {
    if (!isPublicDirectory(_downloadDir)) return true;
    final hasAccess = await hasWriteAccess(_downloadDir);
    if (hasAccess) return true;
    final granted = await requestManageStorage();
    return granted;
  }

  /// 添加下载任务（照搬 CeruMusic downloadSingleSong + addTask 逻辑）
  Future<String> addTask({
    required Song song,
    String? url,
    String quality = '320k',
    int priority = 0,
  }) async {
    // 检查存储权限
    if (!await _ensureStoragePermission()) {
      throw Exception('没有存储权限，请在系统设置中允许「所有文件访问权限」');
    }

    // 检查 WiFi 限制
    if (_wifiOnly) {
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.none)) {
        throw Exception('当前无网络连接');
      }
    }

    // 验证音质是否受当前音源支持
    final sourceId = song.source ?? 'wy';
    final supportedQualities = _qualityValidator?.call(sourceId) ??
        (sourceId == 'local' ? <String>[] : ['128k', '320k', 'flac']);
    if (sourceId != 'local' && !supportedQualities.contains(quality)) {
      throw Exception('UNSUPPORTED_QUALITY:$quality');
    }

    // 构建文件路径
    final filePath = await DownloadTask.buildFilePath(
      downloadDir: _downloadDir,
      title: song.title,
      artist: song.artist,
      quality: quality,
    );

    // 重复检测（照搬 CeruMusic 逻辑）
    for (final existing in _tasks) {
      if (existing.filePath == filePath) {
        if (existing.status == DownloadStatus.completed) {
          final file = File(filePath);
          if (await file.exists()) {
            throw Exception('歌曲已下载完成');
          }
        }
        if (existing.status == DownloadStatus.downloading ||
            existing.status == DownloadStatus.queued ||
            existing.status == DownloadStatus.paused) {
          throw Exception('歌曲正在下载中');
        }
      }
    }

    // 照搬 CeruMusic downloadSingleSong：先获取 URL，再创建任务
    String resolvedUrl = url ?? '';
    if (resolvedUrl.isEmpty && _urlFetcher != null) {
      final tempTask = DownloadTask(
        id: '',
        song: song,
        url: '',
        quality: quality,
        filePath: filePath,
        priority: priority,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      final fetchedUrl = await _urlFetcher!(tempTask);
      if (fetchedUrl != null && fetchedUrl.isNotEmpty) {
        resolvedUrl = fetchedUrl;
      }
    }

    final task = DownloadTask(
      id: DownloadTask.generateId(),
      song: song,
      url: resolvedUrl,
      quality: quality,
      filePath: filePath,
      priority: priority,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    _tasks.add(task);
    await _saveTasks();
    _emitUpdate();
    _processQueue();
    onTaskStarted?.call(task);
    return task.id;
  }

  /// 批量添加下载任务
  Future<void> addTasks(List<({Song song, String quality})> items) async {
    for (int i = 0; i < items.length; i++) {
      try {
        await addTask(
          song: items[i].song,
          quality: items[i].quality,
          priority: i,
        );
      } catch (e) {
        debugPrint('[DownloadRepository] 批量添加失败: $e');
      }
    }
  }

  /// 暂停任务
  Future<void> pauseTask(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];
    if (task.status != DownloadStatus.downloading &&
        task.status != DownloadStatus.queued) {
      return;
    }

    _initializingTasks.remove(taskId);
    _fileLocks.remove(task.filePath);
    _cancelTokens[taskId]?.cancel();
    _cancelTokens.remove(taskId);
    _lastProgressTime.remove(taskId);
    _lastProgressBytes.remove(taskId);

    if (task.status == DownloadStatus.downloading) {
      _activeDownloads--;
    }

    _tasks[index] = task.copyWith(status: DownloadStatus.paused);
    await _saveTasks();
    _emitUpdate();
    _processQueue();
  }

  /// 恢复任务（照搬 CeruMusic resumeTask：放入队列头部）
  Future<void> resumeTask(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];
    if (task.status != DownloadStatus.paused &&
        task.status != DownloadStatus.error &&
        task.status != DownloadStatus.cancelled) {
      return;
    }

    _initializingTasks.remove(taskId);
    _fileLocks.remove(task.filePath);

    _tasks[index] = task.copyWith(
      status: DownloadStatus.queued,
      retries: 0,
      error: null,
    );
    await _saveTasks();
    _emitUpdate();
    _processQueue();
  }

  /// 重试任务
  Future<void> retryTask(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    _initializingTasks.remove(taskId);
    _fileLocks.remove(_tasks[index].filePath);

    _tasks[index] = _tasks[index].copyWith(
      status: DownloadStatus.queued,
      progress: 0,
      downloadedSize: 0,
      speed: 0,
      remainingTime: null,
      retries: 0,
      error: null,
    );
    await _saveTasks();
    _emitUpdate();
    _processQueue();
  }

  /// 取消任务
  Future<void> cancelTask(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];
    _initializingTasks.remove(taskId);
    _fileLocks.remove(task.filePath);

    if (task.status == DownloadStatus.downloading) {
      _cancelTokens[taskId]?.cancel();
      _cancelTokens.remove(taskId);
      _lastProgressTime.remove(taskId);
      _lastProgressBytes.remove(taskId);
      _activeDownloads--;

      final tempFile = File('${task.filePath}.temp');
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }

    _tasks[index] = task.copyWith(status: DownloadStatus.cancelled);
    await _saveTasks();
    _emitUpdate();
    _processQueue();
  }

  /// 删除任务
  Future<void> deleteTask(String taskId, {bool deleteFile = false}) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];

    _initializingTasks.remove(taskId);
    _fileLocks.remove(task.filePath);

    if (task.status == DownloadStatus.downloading) {
      _cancelTokens[taskId]?.cancel();
      _cancelTokens.remove(taskId);
      _lastProgressTime.remove(taskId);
      _lastProgressBytes.remove(taskId);
      _activeDownloads--;
    }

    if (deleteFile) {
      final file = File(task.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      final tempFile = File('${task.filePath}.temp');
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }

    _tasks.removeAt(index);
    await _saveTasks();
    _emitUpdate();
    _processQueue();
  }

  /// 暂停所有任务
  Future<void> pauseAllTasks() async {
    for (int i = 0; i < _tasks.length; i++) {
      final task = _tasks[i];
      if (task.status == DownloadStatus.downloading) {
        _cancelTokens[task.id]?.cancel();
        _cancelTokens.remove(task.id);
        _lastProgressTime.remove(task.id);
        _lastProgressBytes.remove(task.id);
        _activeDownloads--;
        _initializingTasks.remove(task.id);
        _fileLocks.remove(task.filePath);
        _tasks[i] = task.copyWith(status: DownloadStatus.paused);
      } else if (task.status == DownloadStatus.queued) {
        _initializingTasks.remove(task.id);
        _fileLocks.remove(task.filePath);
        _tasks[i] = task.copyWith(status: DownloadStatus.paused);
      }
    }
    await _saveTasks();
    _emitUpdate();
    _processQueue();
  }

  /// 恢复所有暂停的任务
  Future<void> resumeAllTasks() async {
    final pausedTasks = _tasks
        .where((t) => t.status == DownloadStatus.paused)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final task in pausedTasks) {
      await resumeTask(task.id);
    }
  }

  /// 清空任务
  Future<void> clearTasks(String type) async {
    final toRemove = <String>[];
    for (final task in _tasks) {
      switch (type) {
        case 'queue':
          if (task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.queued ||
              task.status == DownloadStatus.paused) {
            toRemove.add(task.id);
          }
          break;
        case 'completed':
          if (task.status == DownloadStatus.completed) {
            toRemove.add(task.id);
          }
          break;
        case 'failed':
          if (task.status == DownloadStatus.error ||
              task.status == DownloadStatus.cancelled) {
            toRemove.add(task.id);
          }
          break;
        case 'all':
          toRemove.add(task.id);
          break;
      }
    }
    _initializingTasks.clear();
    _fileLocks.clear();
    _activeDownloads = 0;
    for (final id in toRemove) {
      await deleteTask(id);
    }
  }

  /// 设置最大并发数
  void setMaxConcurrent(int max) {
    _maxConcurrent = max;
    _processQueue();
  }

  // ==================== 队列处理 ====================

  void _processQueue() {
    while (_activeDownloads + _initializingTasks.length < _maxConcurrent) {
      int bestIndex = -1;
      int bestPriority = 999999;
      for (int i = 0; i < _tasks.length; i++) {
        if (_tasks[i].status == DownloadStatus.queued) {
          if (_tasks[i].priority < bestPriority) {
            bestPriority = _tasks[i].priority;
            bestIndex = i;
          }
        }
      }
      if (bestIndex == -1) break;

      final task = _tasks[bestIndex];
      _startTask(task.id);
    }
  }

  Future<void> _startTask(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    _initializingTasks.add(taskId);

    _tasks[index] = _tasks[index].copyWith(status: DownloadStatus.downloading);
    _emitUpdate();

    try {
      var task = _tasks[index];
      String url = task.url;
      if (url.isEmpty && _urlFetcher != null) {
        final fetchedUrl = await _urlFetcher!(task);
        if (fetchedUrl == null || fetchedUrl.isEmpty) {
          _initializingTasks.remove(taskId);
          _markError(taskId, '无法获取播放链接');
          return;
        }
        url = fetchedUrl;
        task = task.copyWith(url: url);
        _tasks[index] = task;
      }

      if (url.isEmpty) {
        _initializingTasks.remove(taskId);
        _markError(taskId, '无法获取播放链接');
        return;
      }

      if (_fileLocks.containsKey(task.filePath)) {
        _initializingTasks.remove(taskId);
        _markError(taskId, '歌曲正在下载中');
        return;
      }
      _fileLocks[task.filePath] = true;

      _initializingTasks.remove(taskId);
      _activeDownloads++;

      await _downloadFile(taskId, url);
    } catch (e) {
      debugPrint('[DownloadRepository] 下载失败: $e');
      _initializingTasks.remove(taskId);
      final idx = _tasks.indexWhere((t) => t.id == taskId);
      final filePath = idx != -1 ? _tasks[idx].filePath : '';
      _handleError(taskId, e.toString(), tempFilePath: filePath);
    }
  }

  void _markError(String taskId, String error) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx != -1) {
      _tasks[idx] = _tasks[idx].copyWith(
        status: DownloadStatus.error,
        error: error,
        speed: 0,
      );
      _saveTasks();
      _emitUpdate();
    }
    _processQueue();
  }

  Future<void> _downloadFile(String taskId, String url) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];
    final filePath = task.filePath;
    final tempPath = '$filePath.temp';

    final cancelToken = CancelToken();
    _cancelTokens[taskId] = cancelToken;
    _lastProgressTime[taskId] = DateTime.now();
    _lastProgressBytes[taskId] = 0;

    try {
      // 检查是否有已下载的部分（支持断点续传）
      final tempFile = File(tempPath);
      int startByte = 0;
      if (await tempFile.exists()) {
        startByte = await tempFile.length();
        _tasks[index] = _tasks[index].copyWith(
          downloadedSize: startByte,
        );
        _emitUpdate();
      }

      final headers = <String, String>{};
      if (startByte > 0) {
        headers['Range'] = 'bytes=$startByte-';
      }

      final response = await _dio.download(
        url,
        tempPath,
        cancelToken: cancelToken,
        deleteOnError: false,
        options: Options(headers: headers),
        onReceiveProgress: (received, total) {
          final totalWithOffset = total > 0 ? total + startByte : 0;
          final receivedWithOffset = received + startByte;

          // 计算速度
          final now = DateTime.now();
          final lastTime = _lastProgressTime[taskId];
          final lastBytes = _lastProgressBytes[taskId] ?? 0;

          double speed = 0;
          int? remainingTime;
          if (lastTime != null && totalWithOffset > 0) {
            final elapsed = now.difference(lastTime).inMilliseconds;
            if (elapsed > 0) {
              final bytesDiff = receivedWithOffset - lastBytes;
              speed = bytesDiff * 1000 / elapsed; // bytes/s
              final remaining = totalWithOffset - receivedWithOffset;
              if (speed > 0) {
                remainingTime = (remaining / speed).round();
              }
            }
          }

          _lastProgressTime[taskId] = now;
          _lastProgressBytes[taskId] = receivedWithOffset;

          final progress = totalWithOffset > 0
              ? receivedWithOffset / totalWithOffset
              : 0.0;

          final idx = _tasks.indexWhere((t) => t.id == taskId);
          if (idx != -1) {
            _tasks[idx] = _tasks[idx].copyWith(
              progress: progress.clamp(0.0, 1.0),
              totalSize: totalWithOffset,
              downloadedSize: receivedWithOffset,
              speed: speed,
              remainingTime: remainingTime,
            );
            _emitUpdate();
          }
        },
      );

      if (response.statusCode == 200 || response.statusCode == 206) {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          await tempFile.rename(filePath);
        }

        String finalPath = filePath;
        try {
          final detected = await _detectAudioFormat(filePath);
          final shouldExt = _extForFormat(detected);
          final curExt = filePath.substring(filePath.lastIndexOf('.'));
          if (shouldExt.isNotEmpty && shouldExt != curExt) {
            final baseNoExt = filePath.substring(0, filePath.lastIndexOf('.'));
            var proposed = '$baseNoExt$shouldExt';
            if (await File(proposed).exists()) {
              proposed = '$baseNoExt.${DateTime.now().millisecondsSinceEpoch}$shouldExt';
            }
            await File(filePath).rename(proposed);
            finalPath = proposed;
          }
        } catch (_) {}

        // 写入标签（对齐 CeruMusic processSongFiles 逻辑）
        try {
          final tagOpts = _tagWriteOptionsFetcher?.call() ?? const TagWriteOptions();
          Song songForTag = task.song;
          debugPrint('[DownloadRepository] 标签写入选项: basicInfo=${tagOpts.basicInfo}, cover=${tagOpts.cover}, lyrics=${tagOpts.lyrics}, downloadLyrics=${tagOpts.downloadLyrics}, lyricFormat=${tagOpts.lyricFormat}');
          debugPrint('[DownloadRepository] 歌词获取器: ${_lyricFetcher != null}, song.lrc: ${songForTag.lrc != null ? "has ${songForTag.lrc!.length} chars" : "null"}');
          if ((tagOpts.lyrics || tagOpts.downloadLyrics) && _lyricFetcher != null) {
            try {
              final lrc = await _lyricFetcher!(songForTag);
              debugPrint('[DownloadRepository] 歌词获取结果: ${lrc != null ? "has ${lrc.length} chars" : "null"}');
              if (lrc != null && lrc.isNotEmpty) {
                songForTag = songForTag.copyWith(lrc: lrc);
              }
            } catch (e) {
              debugPrint('[DownloadRepository] 获取歌词失败: $e');
            }
          }
          await _tagWriteService.processSongFiles(
            finalPath,
            songForTag,
            basicInfo: tagOpts.basicInfo,
            cover: tagOpts.cover,
            lyrics: tagOpts.lyrics,
            downloadLyrics: tagOpts.downloadLyrics,
            lyricFormat: tagOpts.lyricFormat,
          );
        } catch (e) {
          debugPrint('[DownloadRepository] 标签写入失败: $e');
        }

        final idx = _tasks.indexWhere((t) => t.id == taskId);
        if (idx != -1) {
          _tasks[idx] = _tasks[idx].copyWith(
            progress: 1.0,
            status: DownloadStatus.completed,
            speed: 0,
            remainingTime: 0,
            filePath: finalPath,
          );
          await _saveTasks();
          _emitUpdate();
          onTaskCompleted?.call(_tasks[idx]);
          // 通知 MediaStore 扫描新文件，使其在本地音乐中可见
          scanFileInMediaStore(finalPath);
        }
        _fileLocks.remove(filePath);
        _activeDownloads--;
        _processQueue();
      } else {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        _handleError(taskId, '下载失败: HTTP ${response.statusCode}', tempFilePath: filePath);
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;

      final idx = _tasks.indexWhere((t) => t.id == taskId);
      if (idx != -1) {
        final task = _tasks[idx];
        if (task.retries < _maxRetries) {
          _tasks[idx] = task.copyWith(
            status: DownloadStatus.queued,
            retries: task.retries + 1,
          );
          await _saveTasks();
          _emitUpdate();
          _fileLocks.remove(task.filePath);
          _activeDownloads--;
          _processQueue();
          return;
        }
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        _handleError(taskId, e.message ?? '下载失败', tempFilePath: task.filePath);
      }
    } catch (e) {
      final idx = _tasks.indexWhere((t) => t.id == taskId);
      if (idx != -1) {
        final task = _tasks[idx];
        if (task.retries < _maxRetries) {
          _tasks[idx] = task.copyWith(
            status: DownloadStatus.queued,
            retries: task.retries + 1,
          );
          await _saveTasks();
          _emitUpdate();
          _fileLocks.remove(task.filePath);
          _activeDownloads--;
          _processQueue();
          return;
        }
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        _handleError(taskId, e.toString(), tempFilePath: task.filePath);
      }
    } finally {
      _cancelTokens.remove(taskId);
      _lastProgressTime.remove(taskId);
      _lastProgressBytes.remove(taskId);
    }
  }

  void _handleError(String taskId, String error, {String? tempFilePath}) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx != -1) {
      _fileLocks.remove(_tasks[idx].filePath);
      _tasks[idx] = _tasks[idx].copyWith(
        status: DownloadStatus.error,
        error: error,
        speed: 0,
      );
      _saveTasks();
      _emitUpdate();
      onTaskError?.call(_tasks[idx], error);
    }
    if (tempFilePath != null) {
      final tempFile = File('$tempFilePath.temp');
      if (tempFile.existsSync()) {
        tempFile.delete();
      }
    }
    _activeDownloads--;
    _processQueue();
  }

  // ==================== 查询 ====================

  List<DownloadTask> getDownloadTasks() => List.unmodifiable(_tasks);

  List<DownloadTask> getTasksByStatus(DownloadStatus status) {
    return _tasks.where((t) => t.status == status).toList();
  }

  bool isSongDownloaded(String songId) {
    return _tasks.any((t) =>
        t.song.id == songId && t.status == DownloadStatus.completed);
  }

  String? getDownloadedPath(String songId) {
    final task = _tasks.cast<DownloadTask?>().firstWhere(
          (t) => t!.song.id == songId && t.status == DownloadStatus.completed,
          orElse: () => null,
        );
    if (task != null) {
      final file = File(task.filePath);
      if (file.existsSync()) return task.filePath;
    }
    return null;
  }

  // ==================== 持久化 ====================

  Future<void> _saveTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = jsonEncode(_tasks.map((t) => t.toJson()).toList());
      await prefs.setString(_tasksKey, tasksJson);
    } catch (e) {
      debugPrint('[DownloadRepository] 保存任务失败: $e');
    }
  }

  void _emitUpdate() {
    if (!_taskController.isClosed) {
      _taskController.add(List.unmodifiable(_tasks));
    }
  }

  // ==================== 格式检测（照搬 CeruMusic detectFormat） ====================

  Future<String> _detectAudioFormat(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return '';
      final raf = await file.open(mode: FileMode.read);
      final header = await raf.read(64);
      await raf.close();

      if (header.length < 4) return '';

      final s3 = String.fromCharCodes(header.sublist(0, 3));
      final s4 = String.fromCharCodes(header.sublist(0, 4));
      final sFtyp = header.length >= 12
          ? String.fromCharCodes(header.sublist(4, 8))
          : '';

      if (s3 == 'ID3') return 'mp3';
      if (s4 == 'fLaC') return 'flac';
      if (header[0] == 0x4f && header[1] == 0x67 && header[2] == 0x67 && header[3] == 0x53) return 'ogg';
      if (header[0] == 0x30 && header[1] == 0x26 && header[2] == 0xb2 && header[3] == 0x75) return 'wma';
      if (header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46 &&
          header[8] == 0x57 && header[9] == 0x41 && header[10] == 0x56 && header[11] == 0x45) {
        return 'wav';
      }
      if (sFtyp == 'ftyp') return 'm4a';
      if (header[0] == 0xff && (header[1] & 0xe0) == 0xe0) return 'mp3';

      return '';
    } catch (_) {
      return '';
    }
  }

  String _extForFormat(String format) {
    switch (format) {
      case 'mp3': return '.mp3';
      case 'flac': return '.flac';
      case 'm4a': return '.m4a';
      case 'wav': return '.wav';
      case 'ogg': return '.ogg';
      case 'wma': return '.wma';
      default: return '';
    }
  }

  void dispose() {
    _dio.close();
    _taskController.close();
  }
}
