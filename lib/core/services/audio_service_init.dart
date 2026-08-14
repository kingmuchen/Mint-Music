import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/player/platform/audio_handler.dart';

MusicAudioHandler? _audioHandler;

MusicAudioHandler get audioHandler {
  if (_audioHandler == null) {
    throw StateError('AudioService 未初始化，请先调用 initAudioService()');
  }
  return _audioHandler!;
}

Future<void> initAudioService() async {
  debugPrint('[AudioService] 开始初始化');
  
  _audioHandler = await AudioService.init(
    builder: () => MusicAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.mintmusic.channel.audio',
      androidNotificationChannelName: '音乐播放',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'mipmap/logo',
      androidShowNotificationBadge: false,
      notificationColor: const Color(0xFF1DB954),
    ),
  );
  
  debugPrint('[AudioService] 初始化完成');
}
