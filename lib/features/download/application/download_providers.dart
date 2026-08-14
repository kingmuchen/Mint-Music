import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../local/application/local_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../../plugin/application/plugin_providers.dart';
import '../data/download_repository.dart';
import '../domain/models/download_task.dart';

class DownloadNotification {
  final String message;
  final Color? backgroundColor;
  DownloadNotification({required this.message, this.backgroundColor});
}

final downloadNotificationProvider = StateProvider<DownloadNotification?>((ref) => null);

final downloadRepositoryProvider = Provider<DownloadRepository>((ref) {
  final repo = DownloadRepository();
  bool initialized = false;

  // 当下载目录变化时，自动注册到本地音乐扫描器
  repo.onDirectoryChanged = (dir) {
    final localRepo = ref.read(localMusicRepositoryProvider);
    localRepo.addDirectory(dir);
  };

  // 从设置中读取下载配置并初始化
  ref.listen<AsyncValue<void>>(settingsInitProvider, (prev, next) async {
    if (next is AsyncData && !initialized) {
      initialized = true;
      final svc = await ref.read(settingsServiceProvider.future);
      repo.init(
        downloadDir: await svc.getDownloadDir(),
        wifiOnly: svc.getWifiOnlyDownload(),
        maxConcurrent: 3,
      );
    }
  }, fireImmediately: true);

  // 设置 URL 获取器
  final musicSourceManager = ref.read(musicSourceManagerProvider);
  repo.setUrlFetcher((task) async {
    return await musicSourceManager.getMusicUrl(task.song, quality: task.quality);
  });

  // 设置标签写入选项获取器（对齐 CeruMusic tagWriteOptions）
  repo.setTagWriteOptionsFetcher(() {
    return TagWriteOptions(
      basicInfo: ref.read(tagWriteBasicInfoProvider),
      cover: ref.read(tagWriteCoverProvider),
      lyrics: ref.read(tagWriteLyricsProvider),
      downloadLyrics: ref.read(tagWriteDownloadLyricsProvider),
      lyricFormat: ref.read(tagWriteLyricFormatProvider),
    );
  });

  // 设置歌词获取器（下载时若歌词为空则实时获取）
  repo.setLyricFetcher((song) async {
    try {
      return await musicSourceManager.getLyric(song);
    } catch (e) {
      return null;
    }
  });

  // 设置音质验证器
  repo.setQualityValidator((sourceId) {
    return musicSourceManager.getSupportedQualitiesForSourceId(sourceId);
  });

  // 下载通知回调
  repo.onTaskStarted = (task, {backgroundColor}) {
    ref.read(downloadNotificationProvider.notifier).state = DownloadNotification(
      message: '开始下载 ${task.song.title}',
    );
  };
  repo.onTaskCompleted = (task, {backgroundColor}) {
    ref.read(downloadNotificationProvider.notifier).state = DownloadNotification(
      message: '${task.song.title} 下载完成',
    );
  };
  repo.onTaskError = (task, error, {backgroundColor}) {
    ref.read(downloadNotificationProvider.notifier).state = DownloadNotification(
      message: '${task.song.title} 下载失败',
      backgroundColor: backgroundColor ?? Colors.red,
    );
  };

  // 监听设置变化
  ref.listen(downloadDirProvider, (prev, next) {
    repo.updateSettings(downloadDir: next);
  });
  ref.listen(wifiOnlyDownloadProvider, (prev, next) {
    repo.updateSettings(wifiOnly: next);
  });

  ref.onDispose(() => repo.dispose());
  return repo;
});

final downloadTasksProvider = StreamProvider<List<DownloadTask>>((ref) {
  final repo = ref.watch(downloadRepositoryProvider);
  return repo.taskStream;
});

final downloadSearchQueryProvider = StateProvider<String>((ref) => '');

final filteredDownloadTasksProvider = Provider<List<DownloadTask>>((ref) {
  final query = ref.watch(downloadSearchQueryProvider);
  final tasksAsync = ref.watch(downloadTasksProvider);
  return tasksAsync.when(
    data: (tasks) {
      if (query.isEmpty) return tasks;
      return tasks
          .where((t) =>
              t.song.title.toLowerCase().contains(query.toLowerCase()) ||
              t.song.artist.toLowerCase().contains(query.toLowerCase()))
          .toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

final downloadStatsProvider = Provider<({
  int total,
  int downloading,
  int completed,
  int failed,
})>((ref) {
  final tasksAsync = ref.watch(downloadTasksProvider);
  return tasksAsync.when(
    data: (tasks) {
      final downloading = tasks.where((t) =>
          t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.queued).length;
      final completed = tasks.where((t) => t.status == DownloadStatus.completed).length;
      final failed = tasks.where((t) =>
          t.status == DownloadStatus.error ||
          t.status == DownloadStatus.cancelled).length;
      return (total: tasks.length, downloading: downloading, completed: completed, failed: failed);
    },
    loading: () => (total: 0, downloading: 0, completed: 0, failed: 0),
    error: (_, __) => (total: 0, downloading: 0, completed: 0, failed: 0),
  );
});
