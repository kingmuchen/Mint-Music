import 'dart:io';
import 'package:uuid/uuid.dart';
import '../../../player/domain/models/song.dart';

const _uuid = Uuid();

enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  error,
  cancelled,
}

class DownloadTask {
  final String id;
  final Song song;
  final String url;
  final String quality;
  final String filePath;
  final DownloadStatus status;
  final double progress;
  final int totalSize;
  final int downloadedSize;
  final double speed;
  final int? remainingTime;
  final int retries;
  final String? error;
  final int priority;
  final int createdAt;

  const DownloadTask({
    required this.id,
    required this.song,
    required this.url,
    required this.quality,
    required this.filePath,
    this.status = DownloadStatus.queued,
    this.progress = 0,
    this.totalSize = 0,
    this.downloadedSize = 0,
    this.speed = 0,
    this.remainingTime,
    this.retries = 0,
    this.error,
    this.priority = 0,
    required this.createdAt,
  });

  DownloadTask copyWith({
    String? id,
    Song? song,
    String? url,
    String? quality,
    String? filePath,
    DownloadStatus? status,
    double? progress,
    int? totalSize,
    int? downloadedSize,
    double? speed,
    int? remainingTime,
    int? retries,
    String? error,
    int? priority,
    int? createdAt,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      song: song ?? this.song,
      url: url ?? this.url,
      quality: quality ?? this.quality,
      filePath: filePath ?? this.filePath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      totalSize: totalSize ?? this.totalSize,
      downloadedSize: downloadedSize ?? this.downloadedSize,
      speed: speed ?? this.speed,
      remainingTime: remainingTime ?? this.remainingTime,
      retries: retries ?? this.retries,
      error: error ?? this.error,
      priority: priority ?? this.priority,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'song': song.toJson(),
    'url': url,
    'quality': quality,
    'filePath': filePath,
    'status': status.name,
    'progress': progress,
    'totalSize': totalSize,
    'downloadedSize': downloadedSize,
    'speed': speed,
    'remainingTime': remainingTime,
    'retries': retries,
    'error': error,
    'priority': priority,
    'createdAt': createdAt,
  };

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] ?? '',
      song: Song.fromJson(json['song']),
      url: json['url'] ?? '',
      quality: json['quality'] ?? '320k',
      filePath: json['filePath'] ?? '',
      status: DownloadStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => DownloadStatus.queued,
      ),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      totalSize: json['totalSize'] ?? 0,
      downloadedSize: json['downloadedSize'] ?? 0,
      speed: (json['speed'] as num?)?.toDouble() ?? 0,
      remainingTime: json['remainingTime'],
      retries: json['retries'] ?? 0,
      error: json['error'],
      priority: json['priority'] ?? 0,
      createdAt: json['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  static String generateId() => _uuid.v4();

  static Future<String> buildFilePath({
    required String downloadDir,
    required String title,
    required String artist,
    required String quality,
    String? extension,
  }) async {
    final dir = Directory(downloadDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final ext = _extensionFromQuality(quality, extension);
    final safeTitle = _sanitizeFilename('$title - $artist');
    return '${dir.path}/$safeTitle.$ext';
  }

  static String _extensionFromQuality(String quality, String? original) {
    if (original != null && original.isNotEmpty) return original;
    switch (quality) {
      case 'flac':
      case 'flac24bit':
      case 'hires':
      case 'atmos':
      case 'master':
        return 'flac';
      case '128k':
      case '320k':
      default:
        return 'mp3';
    }
  }

  static String _sanitizeFilename(String name) {
    return name
        .replaceAll(RegExp(r'[/\\:*?"<>|]'), '')
        .replaceAll(RegExp(r'^\.+'), '')
        .replaceAll(RegExp(r'\.+$'), '')
        .trim();
  }
}
