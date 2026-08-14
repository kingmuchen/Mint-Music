# 🎵 澜音 Flutter - 仿 CeruMusic 安卓音乐播放器开发文档

> **项目代号**：CeruFlutter（澜音 Flutter 版）
> **目标平台**：Android（后续可扩展至 iOS）
> **框架**：Flutter 3.x+ / Dart 3.x+
> **灵感来源**：[CeruMusic](https://github.com/timeshiftsauce/CeruMusic) — 一款基于 Electron + Vue 3 的开源桌面音乐播放框架

---

## 📋 目录

1. [项目概述](#1-项目概述)
2. [技术栈选型](#2-技术栈选型)
3. [项目架构](#3-项目架构)
4. [UI/UX 设计规范](#4-uiux-设计规范)
5. [核心功能模块](#5-核心功能模块)
6. [插件系统设计](#6-插件系统设计)
7. [数据持久化](#7-数据持久化)
8. [音频引擎](#8-音频引擎)
9. [Android 平台适配](#9-android-平台适配)
10. [性能优化](#10-性能优化)
11. [错误处理与日志](#11-错误处理与日志)
12. [测试策略](#12-测试策略)
13. [开发路线图](#13-开发路线图)
14. [目录结构](#14-目录结构)

---

## 1. 项目概述

### 1.1 项目定位

**澜音 Flutter** 是一个基于 Flutter 构建的开源 Android 音乐播放器，借鉴 CeruMusic 的核心理念：

- **框架而非产品**：提供一个完整的音乐播放 UI 框架和插件运行环境
- **插件化音源**：自身不提供任何音乐资源，通过插件系统加载音源
- **精美 UI**：继承 CeruMusic 优雅的视觉风格，充分利用 Flutter 的渲染能力
- **隐私优先**：所有数据本地存储，无云端同步

### 1.2 核心原则

| 原则 | 说明 |
|------|------|
| **合规性** | 严格遵守版权法规，不提供、不存储任何版权内容 |
| **模块化** | 核心功能与音源完全解耦 |
| **性能优先** | 虚拟列表、懒加载、内存优化 |
| **用户体验** | 流畅动画、沉浸式播放体验、高度可定制主题 |

### 1.3 目标用户

- **普通用户**：通过安装插件获取音乐播放能力
- **插件开发者**：遵循插件规范开发各类音源插件
- **学习者**：学习 Flutter 复杂应用架构设计的开发者

---

## 2. 技术栈选型

### 2.1 核心框架

| 技术 | 版本要求 | 用途 |
|------|---------|------|
| Flutter | >=3.22.0 | 跨平台 UI 框架 |
| Dart | >=3.4.0 | 开发语言 |
| Android SDK | minSdk 24+, targetSdk 34+ | Android 平台目标 |

> **注意**：以下依赖版本为参考值，实际开发时请查阅最新版本。

### 2.2 状态管理

推荐方案：**Riverpod 2.x**（或 Bloc 8.x）

```yaml
# pubspec.yaml
dependencies:
  flutter_riverpod: ^2.5.0       # 响应式状态管理
  riverpod_annotation: ^2.3.0    # 代码生成注解
  freezed_annotation: ^2.4.0     # 不可变数据类注解
  json_annotation: ^4.9.0        # JSON 序列化注解

dev_dependencies:
  build_runner: ^2.4.0
  freezed: ^2.5.0
  json_serializable: ^6.8.0
```

> **提示**：早期开发阶段可先用普通 Dart 类 + 手动 `==`/`hashCode` 快速迭代，后续再迁移到 freezed。

### 2.3 音频播放

```yaml
dependencies:
  just_audio: ^0.9.36            # 核心音频播放引擎
  audio_service: ^0.18.12        # 后台音频播放服务
  audio_session: ^0.1.19         # 音频会话管理（蓝牙、外放切换）

# 可选：高性能方案（基于 mpv/ffmpeg）
#  flutter_media_kit: ^1.0.0
```

### 2.4 数据持久化

```yaml
dependencies:
  isar: ^3.1.0                   # 高性能本地数据库（主推，NoSQL）
  isar_flutter_libs: ^3.1.0      # Isar 原生库
  hive_flutter: ^1.1.0           # 轻量键值存储（配置/缓存）

dev_dependencies:
  isar_generator: ^3.1.0
```

### 2.5 网络与插件加载

```yaml
dependencies:
  dio: ^5.4.0                    # HTTP 客户端
  path_provider: ^2.1.0          # 文件系统路径
  permission_handler: ^11.3.0    # 运行时权限请求
```

### 2.6 UI 与动画

```yaml
dependencies:
  shimmer: ^3.0.0                # 骨架屏加载效果
  lottie: ^3.0.0                 # Lottie 动画
  flutter_animate: ^4.5.0        # 声明式动画链
  extended_image: ^8.2.0         # 图片加载/缓存/手势/预解码
```

---

## 3. 项目架构

### 3.1 分层架构图

```
┌─────────────────────────────────────────────────────────┐
│                     Presentation Layer                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐  │
│  │   Pages  │  │ Widgets  │  │  Custom Painters     │  │
│  └────┬─────┘  └────┬─────┘  └──────────┬───────────┘  │
│       └──────────────┴──────────────────┘              │
├─────────────────────────────────────────────────────────┤
│                     State Layer                          │
│  ┌────────────────┐  ┌────────────┐  ┌─────────────┐   │
│  │ Riverpod       │  │ Providers  │  │ Notifiers   │   │
│  │ Providers      │  │ (State)    │  │ (Actions)   │   │
│  └───────┬────────┘  └─────┬──────┘  └──────┬──────┘   │
│          └─────────────────┴─────────────────┘          │
├─────────────────────────────────────────────────────────┤
│                     Service Layer                        │
│  ┌──────────┐  ┌───────────┐  ┌──────────────────────┐  │
│  │ Audio    │  │ Plugin    │  │  Playlist Manager    │  │
│  │ Service  │  │ Engine    │  │  (Repository)        │  │
│  └──────────┘  └───────────┘  └──────────────────────┘  │
├─────────────────────────────────────────────────────────┤
│                     Data Layer                           │
│  ┌──────────┐  ┌───────────┐  ┌──────────────────────┐  │
│  │ Isar DB  │  │ Hive      │  │  File Cache (Disk)   │  │
│  │ (SQLite) │  │ (Config)  │  │  (Covers/Lyrics)     │  │
│  └──────────┘  └───────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### 3.2 数据流

```
用户操作 → Widget → Riverpod Provider → Service Layer
                                              ↓
Plugin Engine (网络请求) 或  Data Layer (本地数据库)
        ↓
   返回数据 → Riverpod State → Widget 重建渲染
```

### 3.3 关键类设计

```dart
// ─── 核心模型 ───
@freezed
class Song with _$Song {
  const factory Song({
    required String id,
    required String title,
    required String artist,
    required String? album,
    required String? coverUrl,
    required String? audioUrl,
    required String? lyricUrl,
    required Duration duration,
    required String? pluginId,        // 来源插件标识
  }) = _Song;
  factory Song.fromJson(Map<String, dynamic> json) => _$SongFromJson(json);
}

@freezed
class Playlist with _$Playlist {
  const factory Playlist({
    required String id,
    required String name,
    required String? description,
    required String? coverUrl,
    required List<String> songIds,     // 歌曲 ID 列表（有序）
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Playlist;
  factory Playlist.fromJson(Map<String, dynamic> json) => _$PlaylistFromJson(json);
}

// ─── 插件接口 ───
abstract class MusicPlugin {
  String get id;
  String get name;
  String get version;
  String? get author;
  String? get description;
  String? get iconUrl;

  /// 搜索歌曲
  Future<List<Song>> search(String keyword, {int page = 1, int pageSize = 20});

  /// 获取歌曲详情（含可播放的音频URL）
  Future<Song> getSongDetail(String songId);

  /// 获取歌词
  Future<LyricData?> getLyric(String songId);

  /// 获取歌单详情
  Future<PlaylistResult?> getPlaylistDetail(String playlistId);

  /// 获取推荐歌单
  Future<List<PlaylistResult>> getRecommendedPlaylists({int page = 1});

  /// 释放资源
  Future<void> dispose();
}
```

---

## 4. UI/UX 设计规范

### 4.1 设计系统

#### 4.1.1 色彩系统

```dart
class AppTheme {
  // 暗色主题（主推）
  static const darkTheme = {
    'background': Color(0xFF0A0A0F),     // 深黑底色
    'surface': Color(0xFF1A1A2E),        // 卡片表面
    'surfaceVariant': Color(0xFF252540),  // 次级表面
    'primary': Color(0xFF6C63FF),        // 主题紫
    'primaryVariant': Color(0xFF8B83FF), // 浅紫
    'accent': Color(0xFFFF6584),         // 强调色（渐变终点）
    'textPrimary': Color(0xFFFFFFFF),
    'textSecondary': Color(0xFFB0B0C3),
    'textTertiary': Color(0xFF6B6B80),
    'divider': Color(0xFF2A2A3E),
  };

  // 亮色主题
  static const lightTheme = {
    'background': Color(0xFFF5F5FA),
    'surface': Color(0xFFFFFFFF),
    'surfaceVariant': Color(0xFFF0F0F5),
    'primary': Color(0xFF6C63FF),
    'primaryVariant': Color(0xFF5A52E0),
    'accent': Color(0xFFFF6584),
    'textPrimary': Color(0xFF1A1A2E),
    'textSecondary': Color(0xFF6B6B80),
    'textTertiary': Color(0xFF9E9EB0),
    'divider': Color(0xFFE0E0EB),
  };
}
```

#### 4.1.2 渐变与玻璃态

```dart
// 播放器背景渐变（随封面色动态变化）
// 使用 PaletteGenerator 从封面图片提取主色，动态生成渐变
class DynamicGradientBackground extends StatelessWidget {
  // 1. 加载封面 → 提取主色调 (PaletteGenerator.fromImageProvider)
  // 2. 生成径向渐变 (从画面中心向外扩散)
  // 3. 叠加音频可视化 CustomPainter
  // 4. 动画过渡背景色变化
}

// 玻璃态卡片
class GlassmorphicCard extends StatelessWidget {
  // ClipRRect + BackdropFilter(ImageFilter.blur(sigmaX: 10, sigmaY: 10))
  // + 半透明背景层 + 微妙的边框辉光
}

// 专辑封面辉光效果
class CoverGlowEffect extends StatelessWidget {
  // 在封面图片下方渲染模糊 + 缩放的副本
  // 使用 BackdropFilter 或 Stack + Opacity
}
```

#### 4.1.3 字体排版

| 层级 | 字号 | 字重 | 用途 |
|------|------|------|------|
| Display | 34sp | Bold | 当前播放歌曲名 |
| Headline | 20sp | SemiBold | 页面标题、歌单名 |
| Title | 16sp | Medium | 列表项标题 |
| Body | 14sp | Regular | 正文内容 |
| Caption | 12sp | Regular | 辅助文字、时间戳 |
| Label | 10sp | Medium | 标签、徽章 |

### 4.2 页面布局

#### 4.2.1 主界面布局

```
┌────────────────────────────────────────────┐
│  Status Bar + SafeArea                      │
├────────────────────────────────────────────┤
│  ┌────┐  ┌─────── 搜索栏 ───────┐  ┌────┐  │
│  │ ☰  │  │  搜索音乐、歌单...   │  │ 🔔 │  │
│  └────┘  └─────────────────────┘  └────┘  │
├────────────────────────────────────────────┤
│  推荐歌单 (水平滚动，PageView)               │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐              │
│  │卡 1│ │卡 2│ │卡 3│ │卡 4│ →             │
│  └────┘ └────┘ └────┘ └────┘              │
├────────────────────────────────────────────┤
│  热门歌曲 (虚拟列表)                        │
│  ┌──────────────────────────────────────┐  │
│  │ ♪ 歌名 1     - 艺术家 1      3:45 │  │
│  ├──────────────────────────────────────┤  │
│  │ ♪ 歌名 2     - 艺术家 2      4:12 │  │
│  ├──────────────────────────────────────┤  │
│  │ ♪ 歌名 3     - 艺术家 3      3:30 │  │
│  ├──────────────────────────────────────┤  │
│  │ ... (虚拟滚动，海量数据)               │  │
│  └──────────────────────────────────────┘  │
├────────────────────────────────────────────┤
│  Mini Player (底部固定，可上滑展开)         │
│  ┌────┐  ┌──────────────┐  ┌──┐  ┌──┐   │
│  │封 面│  │ 歌名 - 歌手  │  │⏸│  │⏭│   │
│  └────┘  └──────────────┘  └──┘  └──┘   │
└────────────────────────────────────────────┘
```

#### 4.2.2 底部导航栏

```dart
enum BottomTab { home, discover, library, settings }

// Tab 1: 首页 - 推荐歌单、热门歌曲
// Tab 2: 发现 - 分类浏览、排行榜
// Tab 3: 我的 - 本地歌单、收藏、历史、下载
// Tab 4: 设置 - 主题、插件管理、缓存、关于
```

#### 4.2.3 全屏播放器

```
┌────────────────────────────────────────────┐
│  ┌────────────────────────────────────────┐ │
│  │              上滑关闭 / 下滑歌词        │ │
│  ├────────────────────────────────────────┤ │
│  │                                        │ │
│  │       ┌────────────────────┐          │ │
│  │       │   专辑封面 (大)     │          │ │
│  │       │   封面辉光动画      │          │ │
│  │       │   音频可视化叠加    │          │ │
│  │       └────────────────────┘          │ │
│  │                                        │ │
│  │  歌名 (Display 字号)                   │ │
│  │  艺术家 - 专辑名                        │ │
│  │                                        │ │
│  │  ────●─────────────── 进度条 ─────      │ │
│  │  1:23                   3:45           │ │
│  │                                        │ │
│  │  ┌──┐  ┌──┐  ┌──────┐  ┌──┐  ┌──┐   │ │
│  │  │⏮│  │⏪│  │ ▶/⏸ │  │⏩│  │⏭│   │ │
│  │  └──┘  └──┘  └──────┘  └──┘  └──┘   │ │
│  │                                        │ │
│  │  歌词 (Apple Music 风格)               │ │
│  │  等待这一刻等了太久                     │ │
│  │  → 此刻我感受到你的温柔 ← (高亮滚动)    │ │
│  │  仿佛世界只剩下你我                     │ │
│  │                                        │ │
│  │  ♡ 收藏  |  播放列表  |  ↓ 下载        │ │
│  └────────────────────────────────────────┘ │
├────────────────────────────────────────────┤
│  Mini Player Indicator Bar                  │
│  ─── 上滑进入全屏 / 下滑收起 ───            │
└────────────────────────────────────────────┘
```

### 4.3 动画与过渡规范

| 场景 | 动画类型 | 时长 | 曲线 |
|------|---------|------|------|
| 页面切换 | SlideTransition | 300ms | easeInOutCubic |
| Mini→全屏播放器 | Hero + 缩放+滑动 | 400ms | easeInOutQuart |
| 歌词高亮切换 | 渐隐渐现 + 上滑 | 200ms | easeOutCubic |
| 播放/暂停 | 图标旋转 + 缩放 | 150ms | easeInOutBack |
| 喜欢/收藏 | 心形弹跳 | 300ms | elasticOut |
| 搜索展开 | Container 渐显 | 250ms | easeOut |
| 列表项入场 | 滑动 + 淡入 | 200ms | easeOut (staggered) |
| 背景色过渡 | 渐变色动画 | 500ms | easeInOutSine |

### 4.4 苹果风格歌词组件

```dart
/// Apple Music 风格歌词组件
class AppleMusicLyrics extends StatefulWidget {
  // 核心特性：
  // 1. 当前行居中放大 + 高亮（字体大小 + 颜色渐变）
  // 2. 过去行上滑 + 缩小 + 变淡
  // 3. 未来行下滑 + 缩小 + 变淡
  // 4. 逐字高亮动画（若歌词包含逐字时间戳）
  // 5. 轻触歌词行跳转到对应时间点
  // 6. 长按复制歌词
  // 7. 滑动切换歌词翻译/罗马音
  // 8. 锁定模式下跟随播放进度自动滚动
  // 9. 无歌词时显示装饰性动画
}
```

### 4.5 AI 悬浮球（CeruMusic 特色功能）

```dart
/// CeruMusic 标志性 AI 助手悬浮球
class AIAssistantFloatBall extends StatefulWidget {
  // 悬浮球跟随手指拖动
  // 吸附到屏幕边缘（左侧/右侧）
  // 展开后显示快捷操作：智能推荐、歌词翻译、相似歌曲
  // 点击弹出 AI 聊天面板
  // 支持语音输入（通过 Android SpeechRecognizer）
  // 使用 AnimatedPositioned + GestureDetector 实现
}
```

### 4.6 着色器背景（Fragment Shader）

```dart
/// 使用 Fragment Shader 生成动态背景
/// CeruMusic 使用 GLSL 着色器实现音乐可视化动态背景
/// Flutter 中可通过 FragmentProgram 加载 .frag 文件
class ShaderBackground extends StatelessWidget {
  // 1. 加载 .frag 着色器文件
  // 2. 将音频频谱数据作为 uniform 传入
  // 3. 使用 AnimatedSampler 驱动帧动画
  // 4. 与专辑封面主色调混合

  // 简化方案：使用 CustomPainter + 数学计算模拟着色器效果
  // 性能更优：Canvas 2D vs Fragment Shader
}
```

---

## 5. 核心功能模块

### 5.1 音频播放引擎

#### 5.1.1 架构

```
AudioService (Flutter Background Isolate via audio_service)
    │
    ├── AudioPlayer (just_audio)
    │      ├── Play/Pause/Stop/Seek
    │      ├── Volume/Balance
    │      ├── Speed Control (0.5x ~ 2.0x)
    │      └── AudioEffect (通过 MethodChannel 调用 Android SDK)
    │
    ├── AudioSession
    │      ├── 音频焦点管理 (AUDIOFOCUS_GAIN/LOSS)
    │      ├── 蓝牙设备连接/断开处理
    │      ├── 有线耳机插拔监听
    │      └── 音频路由切换 (扬声器/听筒/蓝牙)
    │
    └── NotificationService
           ├── 媒体样式通知 (Android MediaStyle)
           ├── 锁屏控制
           ├── 播放进度更新
           └── 播放列表同步
```

#### 5.1.2 关键实现

```dart
class AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();
  late AudioPlayerHandler _audioHandler;

  // 播放队列
  List<Song> _playQueue = [];
  int _currentIndex = 0;

  // 播放模式
  PlayMode _playMode = PlayMode.sequential;

  // 状态流
  Stream<PlaybackState> get playbackState;

  Future<void> playQueue(List<Song> songs, {int startIndex = 0}) async {
    _playQueue = songs;
    _currentIndex = startIndex;

    final sources = songs.map((s) => AudioSource.uri(
      Uri.parse(s.audioUrl!),
      tag: MediaItem(
        id: s.id,
        title: s.title,
        artist: s.artist,
        artUri: Uri.parse(s.coverUrl ?? ''),
        duration: s.duration,
      ),
    )).toList();

    await _player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: startIndex,
    );
    await _player.play();
  }

  // 播放模式切换
  void setPlayMode(PlayMode mode) {
    _playMode = mode;
    switch (mode) {
      case PlayMode.sequential:
        _player.loopMode = LoopMode.off;
        _player.shuffleModeEnabled = false;
        break;
      case PlayMode.repeatAll:
        _player.loopMode = LoopMode.all;
        break;
      case PlayMode.repeatOne:
        _player.loopMode = LoopMode.one;
        break;
      case PlayMode.shuffle:
        _player.shuffleModeEnabled = true;
        break;
    }
  }
}
```

### 5.2 搜索功能

```dart
class SearchService {
  final List<MusicPlugin> _plugins;

  /// 聚合搜索 - 遍历所有可用插件的搜索接口
  Stream<SearchResult> searchAll(String keyword) async* {
    for (final plugin in _plugins) {
      try {
        final results = await plugin.search(keyword);
        yield SearchResult(pluginId: plugin.id, songs: results);
      } on TimeoutException {
        yield SearchResult.error(pluginId: plugin.id,
            error: '搜索超时');
      } catch (e) {
        yield SearchResult.error(pluginId: plugin.id, error: e);
      }
    }
  }

  /// 搜索历史 (Hive 存储，最近 50 条)
  Future<void> saveSearchHistory(String keyword);
  List<String> getSearchHistory();
  Future<void> clearSearchHistory();
}
```

### 5.3 歌单管理

```dart
class PlaylistRepository {
  final Isar _db;

  Future<Playlist> createPlaylist(String name, {String? description});
  Future<void> deletePlaylist(String id);
  Future<void> addSongToPlaylist(String playlistId, String songId);
  Future<void> removeSongFromPlaylist(String playlistId, String songId);
  Future<void> reorderSongs(String playlistId, List<String> newOrder);
  Future<List<Playlist>> getAllPlaylists();
  Future<List<Song>> getPlaylistSongs(String playlistId);

  /// 导入/导出歌单 (JSON 格式)
  Future<String> exportPlaylist(String playlistId);
  Future<Playlist> importPlaylist(String json);
}
```

### 5.4 下载管理

```dart
class DownloadManager {
  // 缓存策略：
  // - 在线听歌时自动缓存（临时，7天后淘汰）
  // - 手动下载（永久保存）
  // - LRU 淘汰策略

  Future<DownloadTask> downloadSong(Song song);   // 永久下载
  Future<void> cacheForOffline(Song song);         // 缓存

  // 缓存管理
  Future<void> clearCache(CacheType type);
  Future<int> getCacheSize();
  Future<void> setMaxCacheSize(int mb);
}
```

### 5.5 播放历史与统计

```dart
class PlayHistoryService {
  Future<void> recordPlay(Song song);
  Future<List<Song>> getRecentPlays({int limit = 50});
  Future<Map<String, int>> getPlayCounts();
  Future<List<Song>> getMostPlayed({int limit = 20});
  Future<Map<int, int>> getMonthlyStats(); // 每月听歌时长统计
}
```

---

## 6. 插件系统设计

### 6.1 架构设计（Flutter 适配方案）

与 Electron 不同，Flutter 无法动态加载 JS 脚本。经过评估，推荐以下方案：

| 方案 | 说明 | 推荐度 |
|------|------|--------|
| **HTTP API 配置驱动** | 插件定义为 JSON/YAML 配置文件，声明 API 端点和响应解析规则 | ⭐⭐⭐ 首选 |
| **Flutter FFI 动态库** | 编译为 `.so` 动态库通过 `dart:ffi` 加载 | ⭐⭐ 高性能场景 |
| **MethodChannel 原生插件** | 通过 Android Plugin 编写原生逻辑 | ⭐⭐ 需写原生代码 |
| **dart_eval 脚本引擎** | 运行时解释执行 Dart 代码 | ⚠ 不推荐（不稳定） |

### 6.2 推荐方案：HTTP API 配置驱动

插件本质上是 **JSON 配置文件 + API 端点规则**，无需动态代码执行。

```json
// 插件描述文件 manifest.json
{
  "id": "demo.source",
  "name": "示例音源",
  "version": "1.0.0",
  "author": "开发者名",
  "minAppVersion": "1.0.0",
  "description": "这是一个示例音源插件",
  "api": {
    "baseUrl": "https://api.example.com/v1",
    "search": {
      "method": "GET",
      "path": "/search",
      "params": {
        "keyword": "{keyword}",
        "page": "{page}",
        "size": "20"
      }
    },
    "songDetail": {
      "method": "GET",
      "path": "/song/{id}"
    },
    "lyric": {
      "method": "GET",
      "path": "/lyric/{id}"
    }
  },
  "parsing": {
    "searchResultPath": "$.data.list",
    "song": {
      "id": "$.id",
      "title": "$.title",
      "artist": "$.artist",
      "album": "$.album",
      "coverUrl": "$.cover",
      "audioUrl": "$.url",
      "duration": "$.duration"
    },
    "lyricPath": "$.data.lyric"
  }
}
```

### 6.3 进阶方案：规则引擎

对于需要更复杂逻辑的场景，可以在 manifest 中声明简单的处理规则：

```json
{
  "transform": {
    "audioUrl": {
      "type": "concat",
      "parts": ["$.baseUrl", "$.path"]
    },
    "coverUrl": {
      "type": "replace",
      "pattern": "\\{size\\}",
      "replacement": "300"
    },
    "duration": {
      "type": "compute",
      "expression": "duration * 1000"
    }
  }
}
```

### 6.4 插件生命周期

```
安装 .cerm 插件包（ZIP 格式，包含 manifest.json + 图标）
      │
      ├── 1. 解压到 app 插件目录
      ├── 2. 解析 manifest.json，校验格式
      ├── 3. 校验签名（可选，增强安全性）
      ├── 4. 注册到 PluginEngine
      │
      ↓
   启用状态
      │
      ├── search   → 发送 HTTP 请求 → 解析 JSON → 返回 Song 列表
      ├── detail   → 发送 HTTP 请求 → 解析 → 返回 Song
      ├── lyric    → 发送 HTTP 请求 → 解析 → 返回 LyricData
      │
      ↓
   禁用/卸载
      ├── 从 PluginEngine 移除注册
      ├── 清除相关缓存数据
      └── 删除插件目录
```

### 6.5 插件市场 UI

```dart
class PluginManagerPage extends StatelessWidget {
  // 已安装插件列表
  // ┌─────────────────────────────────────┐
  // │ [🟢] 示例音源 v1.0.0           [⚙] │
  // │      作者: xxx · 已启用             │
  // ├─────────────────────────────────────┤
  // │ [🔴] 测试音源 v0.5.0           [⚙] │
  // │      作者: yyy · 已禁用  ⬆有更新    │
  // └─────────────────────────────────────┘
  //
  // 操作：启用/禁用、卸载、从文件安装、从URL安装
  // 插件详情页：名称、版本、作者、API 权限声明、更新日志
}
```

---

## 7. 数据持久化

### 7.1 数据模型 (Isar Schema)

```dart
@collection
class SongModel {
  Id id = Isar.autoIncrement();
  late String songId;              // 原始歌曲 ID（来源插件内唯一）
  late String title;
  late String artist;
  String? album;
  String? coverUrl;
  String? localCoverPath;          // 本地缓存路径
  String? audioUrl;
  String? localAudioPath;          // 下载路径
  int durationMs = 0;
  String? pluginId;
  int playCount = 0;
  DateTime? lastPlayedAt;
  DateTime addedAt = DateTime.now();
  bool isFavorite = false;
}

@collection
class PlaylistModel {
  Id id = Isar.autoIncrement();
  late String name;
  String? description;
  String? coverUrl;
  late List<String> songIds;       // 有序歌曲 ID 列表
  DateTime createdAt = DateTime.now();
  DateTime updatedAt = DateTime.now();
}
```

### 7.2 缓存策略

```dart
class CacheManager {
  static const int maxCacheSizeMB = 500;
  static const int coverCacheDays = 30;
  static const int lyricCacheDays = 60;
  static const int tempAudioCacheDays = 7;  // 临时缓存

  /// LRU 淘汰：按最后访问时间排序，删除最旧文件
  Future<void> evictIfNeeded() async {
    final size = await getCacheSizeMB();
    if (size <= maxCacheSizeMB) return;

    // 获取所有缓存文件，按 atime 排序
    // 删除最旧的文件直到低于阈值
  }
}
```

### 7.3 配置存储 (Hive)

```dart
@HiveType(typeId: 0)
class AppConfig extends HiveObject {
  @HiveField(0)
  bool darkMode = true;

  @HiveField(1)
  String themeColor = '#6C63FF';

  @HiveField(2)
  String defaultPlayMode = 'sequential'; // sequential | repeatAll | repeatOne | shuffle

  @HiveField(3)
  bool autoDownloadLyric = true;

  @HiveField(4)
  bool highQualityAudio = false;

  @HiveField(5)
  double playbackSpeed = 1.0;

  @HiveField(6)
  List<String> enabledPluginIds = [];

  @HiveField(7)
  String? lastPlayedSongId;

  @HiveField(8)
  int? lastPlayedPosition; // 秒
}
```

---

## 8. 音频引擎

### 8.1 后台播放 (audio_service)

```dart
class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> onStart() async {
    // 创建通知渠道（Android 8+ 必需）
    final channel = AndroidNotificationChannel(
      'music_playback',
      '音乐播放',
      description: '音乐播放控制通知',
      importance: Importance.low,
    );
    await channel.create();

    // 设置为前台服务
    await AudioServiceBackground.setForeground(true);
  }

  @override
  Future<void> onStop() async {
    await _player.stop();
    await AudioServiceBackground.setForeground(false);
    await super.onStop();
  }

  // 处理通知控制按钮
  @override
  Future<void> onMediaButtonEvent(MediaButtonEvent event) async {
    // 处理蓝牙耳机按键：上一首/下一首/播放/暂停
  }

  // 错误处理：播放失败时自动切到下一首
  @override
  void onPlayerError(String message) {
    _log.severe('播放错误: $message');
    skipToNext();
  }
}
```

### 8.2 音频焦点管理

```dart
class AudioFocusManager {
  /// 请求音频焦点（通过 audio_session 包）
  Future<bool> requestFocus() async {
    final session = await AudioSession.instance;
    final result = await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    ));
    return result;
  }

  /// 处理焦点变化
  /// - 电话呼入 → 暂停
  /// - 其他 App 播放 → 暂停/降低音量
  /// - 导航语音 → 降低音量 (duck)
  void handleFocusChange(AudioInterruption event) {
    switch (event.type) {
      case AudioInterruptionType.paused:
      case AudioInterruptionType.stopped:
        _playbackService.pause();
        break;
      case AudioInterruptionType.ducked:
        _playbackService.setVolume(0.3);
        break;
      case AudioInterruptionType.unducked:
        _playbackService.setVolume(1.0);
        break;
    }
  }
}
```

### 8.3 Android 原生均衡器接口

```kotlin
// MainActivity.kt
class MainActivity : FlutterActivity() {
    private var equalizer: android.media.audiofx.Equalizer? = null
    private var audioSessionId = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "equalizer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "init" -> {
                        audioSessionId = call.argument<Int>("audioSessionId") ?: 0
                        equalizer = Equalizer(0, audioSessionId)
                        result.success(true)
                    }
                    "setBandLevel" -> {
                        val band = call.argument<Int>("band") ?: return@setMethodCallHandler
                        val level = call.argument<Short>("level") ?: return@setMethodCallHandler
                        equalizer?.setBandLevel(band.toShort(), level)
                        result.success(true)
                    }
                }
            }
    }
}
```

---

## 9. Android 平台适配

### 9.1 必要权限

```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

<!-- 前台服务（后台播放必需） -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />

<!-- Android 13+ 通知权限 -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- Android 13+ 媒体权限（如需读取本地文件） -->
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />

<!-- Android 12 及以下 -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />

<!-- 唤醒锁（防止休眠时播放中断） -->
<uses-permission android:name="android.permission.WAKE_LOCK" />

<!-- 蓝牙音频 -->
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

### 9.2 前台服务配置

```xml
<!-- AndroidManifest.xml (application 标签内) -->
<service
    android:name="com.ryanheise.audioservice.AudioService"
    android:foregroundServiceType="mediaPlayback"
    android:exported="false">
    <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
    </intent-filter>
</service>
```

### 9.3 通知渠道

```dart
// Android 8.0+ 通知渠道必须在应用启动时创建
class NotificationChannelSetup {
  static Future<void> setup() async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_notification'),
      ),
    );

    // 创建播放控制通知渠道
    const androidChannel = AndroidNotificationChannel(
      'music_playback',
      '音乐播放',
      description: '控制音乐播放器的播放状态',
      importance: Importance.low,        // 低优先级，不弹出打扰
      playSound: false,
    );

    await androidChannel.create();
  }
}
```

### 9.4 电池优化与休眠

```dart
class BatteryOptimizationManager {
  /// 引导用户忽略电池优化
  Future<void> requestDisableBatteryOptimization() async {
    if (await isBatteryOptimizationDisabled) return;

    // 打开系统设置页，让用户手动关闭优化
    await openAppSettings();
  }

  /// 使用唤醒锁防止 CPU 休眠
  /// 注：仅在播放时持锁，暂停时释放
  Future<void> acquireWakeLock() async {
    // 通过 WakelockPlus 或 MethodChannel
    await WakelockPlus.enable();
  }

  Future<void> releaseWakeLock() async {
    await WakelockPlus.disable();
  }
}
```

### 9.5 音频路由切换

```dart
class AudioRoutingService {
  // 监听蓝牙连接/断开
  // 自动切换到蓝牙耳机/扬声器
  // 处理有线耳机插拔（插上继续播放，拔出暂停）

  void setupAudioRouteListener() {
    audio_session.AudioSession.instance.then((session) {
      session.becomingNoisyEventStream.listen((_) {
        // 耳机拔出 → 暂停播放（Android 自动广播）
        _playbackService.pause();
      });

      session.interruptionEventStream.listen((event) {
        // 处理音频焦点变化
        handleInterruption(event);
      });
    });
  }
}
```

---

## 10. 性能优化

### 10.1 列表性能（虚拟滚动）

```dart
// 使用 ListView.builder 实现虚拟滚动
// 固定 itemExtent 启用回收优化
ListView.builder(
  itemCount: songs.length,
  itemExtent: 64,  // 固定高度，极致回收效率
  itemBuilder: (context, index) => SongTile(song: songs[index]),
)

// 超长列表（>10000）使用分页加载
PagedListView<int, Song>(
  pagingController: _pagingController,
  builderDelegate: PagedChildBuilderDelegate<Song>(
    itemBuilder: (context, song, index) => SongTile(song: song),
    firstPageProgressIndicator: () => const ShimmerSongList(),
    newPageProgressIndicator: () => const ShimmerSongList( itemCount: 5),
  ),
)
```

### 10.2 图片优化

```dart
// 1. 限制解码尺寸（避免解码 4K 封面图）
ExtendedImage.network(
  url,
  width: 200,
  height: 200,
  fit: BoxFit.cover,
  cache: true,
  clearMemoryCacheIfFailed: false,
)

// 2. 预缓存下一首的封面
Future<void> preCacheNextCover(Song currentSong, List<Song> queue) async {
  final nextIndex = queue.indexOf(currentSong) + 1;
  if (nextIndex < queue.length) {
    final nextSong = queue[nextIndex];
    if (nextSong.coverUrl != null) {
      await precacheImage(
        NetworkImage(nextSong.coverUrl!),
        navigatorKey.currentContext!,
      );
    }
  }
}

// 3. 内存缓存 LRU
// extended_image 默认使用 LRU 内存缓存，无需额外配置
```

### 10.3 内存管理

```dart
// 1. 使用 RepaintBoundary 隔离复杂渲染
RepaintBoundary(
  child: AlbumCoverWithGlow(...),
)

// 2. AutomaticKeepAlive 避免不必要重建
class SongListTab extends StatefulWidget {
  @override
  State<SongListTab> createState() => _SongListTabState();
}

class _SongListTabState extends State<SongListTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
}

// 3. 及时释放音频资源
@override
void dispose() {
  _player.dispose();
  _streamSubscriptions.cancel();
  super.dispose();
}
```

### 10.4 启动性能

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 阶段一：显示启动页（同步操作）
  runApp(const SplashApp());

  // 阶段二：并行异步初始化
  final initResults = await Future.wait([
    _initDatabase(),        // Isar 初始化
    _initPluginEngine(),    // 扫描已安装插件
    _initAudioService(),    // 音频服务注册
    _loadAppConfig(),       // 读取 Hive 配置
  ]);

  // 阶段三：进入主应用
  runApp(const CeruFlutterApp());
}

// 延迟初始化：非关键功能按需加载
class LazyInitService {
  // 搜索索引、统计服务等在后台延迟加载
  Future<void> initBackgroundServices() async {
    await Future.delayed(const Duration(seconds: 3));
    // 初始化非关键服务
  }
}
```

### 10.5 包体积优化

```yaml
# android/app/build.gradle
android {
    buildTypes {
        release {
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile(
                'proguard-android-optimize.txt'
            ), 'proguard-rules.pro'
        }
    }
    // 仅构建 ARM64（兼容主流设备）
    splits {
        abi {
            enable true
            reset()
            include 'arm64-v8a'
        }
    }
}
```

---

## 11. 错误处理与日志

### 11.1 错误分类与处理策略

```dart
/// 播放器错误类型
sealed class PlaybackError {
  const PlaybackError(this.message, this.exception);

  final String message;
  final dynamic exception;
}

class NetworkError extends PlaybackError {
  const NetworkError(super.message, super.exception);
  // 处理：重试、显示离线提示、自动切歌
}

class DecodingError extends PlaybackError {
  const DecodingError(super.message, super.exception);
  // 处理：跳过当前歌曲、报告插件问题
}

class PluginError extends PlaybackError {
  const PluginError(this.pluginId, super.message, super.exception);
  final String pluginId;
  // 处理：禁用该插件、通知用户
}

class StorageError extends PlaybackError {
  const StorageError(super.message, super.exception);
  // 处理：清理缓存、提示用户释放空间
}
```

### 11.2 日志系统

```dart
class AppLogger {
  static final _log = Logger('CeruFlutter');

  // 日志级别
  // ERROR  → 影响用户使用的错误（写入文件）
  // WARN   → 可恢复的问题
  // INFO   → 播放/切换/下载等关键事件
  // DEBUG  → 开发调试信息
  // TRACE  → 详细流程追踪

  static void error(String message, [dynamic error, StackTrace? stack]) {
    _log.severe(message, error, stack);
    // 写入本地日志文件
    _writeToFile('ERROR', message, error, stack);
  }

  static void info(String message) {
    _log.info(message);
  }

  /// 将错误日志写入文件，供用户反馈使用
  static Future<void> _writeToFile(
      String level, String message, dynamic error, StackTrace? stack) async {
    final file = File(await _getLogFilePath());
    await file.writeAsString(
      '[${DateTime.now()}] [$level] $message\n'
      '${error != null ? "Error: $error\n" : ""}'
      '${stack != null ? "Stack: $stack\n" : ""}',
      mode: FileMode.append,
    );
  }

  /// 日志文件导出（用于用户反馈）
  static Future<String> exportLogs() async {
    final file = File(await _getLogFilePath());
    if (await file.exists()) {
      return file.readAsString();
    }
    return '无日志';
  }
}
```

### 11.3 优雅降级

```dart
class GracefulDegradation {
  /// 播放失败：自动切到下一首
  static Future<void> onPlayFailed(
      AudioPlaybackService service, Song failedSong) async {
    AppLogger.error('播放失败: ${failedSong.title}');
    await service.skipToNext();

    // 尝试使用低码率版本
    final lowQualityUrl = await _tryGetLowQualityUrl(failedSong);
    if (lowQualityUrl != null) {
      await service.play(failedSong.copyWith(audioUrl: lowQualityUrl));
    }
  }

  /// 插件超时：跳过，不影响其他插件
  static Future<void> onPluginTimeout(String pluginId) async {
    AppLogger.warn('插件超时: $pluginId');
    // 显示 snackbar 提示用户，但应用不崩溃
  }

  /// 存储空间不足：清理缓存 + 提示
  static Future<void> onStorageFull() async {
    await CacheManager.instance.clearTempCache();
    // 显示提示：已清理临时缓存，建议手动清理
  }
}
```

---

## 12. 测试策略

### 12.1 测试金字塔

```
        ┌──────┐
        │ E2E  │  ← 集成测试：播放完整流程、插件加载
       ┌┴──────┴┐
       │ Widget  │  ← UI 测试：页面渲染、交互响应
      ┌┴────────┴┐
      │  Unit    │  ← 单元测试：Model、Repository、Service
      └──────────┘
```

### 12.2 单元测试

```dart
// 测试 PlaylistRepository
void main() {
  late Isar isar;
  late PlaylistRepository repo;

  setUp(() async {
    isar = await Isar.open(
      [PlaylistModelSchema],
      directory: Directory.current.path,
      inspector: false,
    );
    repo = PlaylistRepository(isar);
  });

  tearDown(() async {
    await isar.close();
  });

  group('PlaylistRepository', () {
    test('创建歌单', () async {
      final playlist = await repo.createPlaylist(
        '我的收藏',
        description: '最喜欢的歌',
      );
      expect(playlist.name, '我的收藏');
      expect(playlist.songIds, isEmpty);
    });

    test('添加歌曲到歌单', () async {
      final playlist = await repo.createPlaylist('测试歌单');
      await repo.addSongToPlaylist(playlist.id, 'song_1');
      await repo.addSongToPlaylist(playlist.id, 'song_2');

      final songs = await repo.getPlaylistSongIds(playlist.id);
      expect(songs, ['song_1', 'song_2']);
    });

    test('删除歌单', () async {
      final playlist = await repo.createPlaylist('待删除');
      await repo.deletePlaylist(playlist.id);
      final all = await repo.getAllPlaylists();
      expect(all, isEmpty);
    });
  });
}
```

### 12.3 Widget 测试

```dart
// 测试 SongTile 组件
void main() {
  testWidgets('SongTile 显示歌曲信息', (WidgetTester tester) async {
    final song = Song(
      id: 'test_1',
      title: '夜曲',
      artist: '周杰伦',
      album: '十一月的肖邦',
      duration: Duration(seconds: 225),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongTile(
            song: song,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('夜曲'), findsOneWidget);
    expect(find.text('周杰伦'), findsOneWidget);
    expect(find.text('3:45'), findsOneWidget);
  });
}
```

### 12.4 音频测试注意事项

```dart
// 音频测试在 CI 环境中比较困难，推荐策略：
// 1. 使用 Mock 替换音频播放器
// 2. 测试状态管理逻辑而非音频实际输出
// 3. 集成测试使用真实设备/模拟器

class MockAudioPlayer extends Mock implements AudioPlayer {
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<Duration?> seek(Duration position) async => position;
}
```

---

## 13. 开发路线图

### 📅 阶段一：基础框架 (Week 1-2)

- [x] 项目初始化，搭建分层架构
- [x] Riverpod 状态管理框架
- [x] 主题系统（暗色/亮色 + 自定义色）
- [x] 底部导航与页面路由
- [x] 基础播放引擎集成 (just_audio)

### 📅 阶段二：核心播放功能 (Week 3-4)

- [x] 音频播放（播放/暂停/切歌/进度拖动）
- [x] 播放模式（顺序/循环/随机/单曲循环）
- [x] 播放队列管理（拖拽排序）
- [x] Mini Player 控件
- [x] 媒体通知与锁屏控制
- [x] 后台播放前台服务

### 📅 阶段三：UI 完善 (Week 5-6)

- [x] 全屏播放器页面（含手势上下滑）
- [x] Apple Music 风格歌词组件
- [x] 专辑封面辉光动画
- [x] AI 悬浮球交互
- [x] 列表页骨架屏 + 入场动画
- [x] 页面过渡动画

### 📅 阶段四：本地功能 (Week 7-8)

- [x] 本地歌单管理 (CRUD + 拖拽排序)
- [x] 歌曲收藏/喜欢
- [x] 播放历史 + 统计
- [x] 下载管理 + 缓存策略
- [x] 搜索历史 + 热词推荐

### 📅 阶段五：插件系统 (Week 9-10)

- [x] 配置驱动插件引擎 (HTTP API)
- [x] 插件加载/卸载机制
- [x] 插件市场 UI
- [x] 示例插件开发
- [x] 插件签名验证

### 📅 阶段六：优化与发布 (Week 11-12)

- [x] Android 平台适配（权限/前台服务/音频焦点）
- [x] 性能优化（内存/启动/列表/图片）
- [x] 错误处理 + 日志系统
- [x] 单元测试 + Widget 测试
- [x] 包体积优化
- [x] 发布内测版

---

## 14. 目录结构

```
ceru_flutter/
├── android/                        # Android 原生代码
├── assets/                         # 静态资源
│   ├── fonts/                      # 自定义字体
│   ├── images/                     # 图片资源
│   │   ├── icons/                  # 图标
│   │   ├── backgrounds/            # 默认背景
│   │   └── placeholders/           # 占位图
│   ├── lottie/                     # Lottie 动画
│   └── shaders/                    # GLSL Fragment Shader (.frag)
│
├── lib/
│   ├── main.dart                   # 入口
│   ├── app.dart                    # 根组件 + 路由
│   │
│   ├── core/                       # 核心基础设施
│   │   ├── constants/              # 常量
│   │   │   ├── app_constants.dart
│   │   │   └── theme_constants.dart
│   │   ├── theme/                  # 主题系统
│   │   │   ├── app_theme.dart
│   │   │   ├── color_scheme.dart
│   │   │   └── text_styles.dart
│   │   ├── router/                 # 路由
│   │   │   └── app_router.dart
│   │   ├── utils/                  # 工具类
│   │   │   ├── extensions/
│   │   │   ├── logger.dart
│   │   │   └── debouncer.dart
│   │   └── widgets/               # 通用组件
│   │       ├── glassmorphic_card.dart
│   │       ├── shimmer_loader.dart
│   │       ├── dynamic_gradient.dart
│   │       └── cover_image.dart
│   │
│   ├── data/                      # 数据层
│   │   ├── database/              # 数据库
│   │   │   └── isar_database.dart
│   │   ├── models/                # 数据模型
│   │   │   ├── song.dart
│   │   │   ├── playlist.dart
│   │   │   ├── lyric_data.dart
│   │   │   └── app_config.dart
│   │   ├── repositories/          # 数据仓库
│   │   │   ├── song_repository.dart
│   │   │   ├── playlist_repository.dart
│   │   │   └── config_repository.dart
│   │   └── cache/                 # 缓存
│   │       └── cache_manager.dart
│   │
│   ├── services/                  # 服务层
│   │   ├── audio/                 # 音频
│   │   │   ├── audio_service.dart
│   │   │   ├── audio_handler.dart
│   │   │   ├── audio_focus_manager.dart
│   │   │   └── equalizer_service.dart
│   │   ├── plugin/                # 插件系统
│   │   │   ├── plugin_engine.dart
│   │   │   ├── plugin_loader.dart
│   │   │   ├── models/
│   │   │   │   └── plugin_manifest.dart
│   │   │   └── plugins/
│   │   │       └── demo_plugin.dart
│   │   ├── download/
│   │   │   └── download_manager.dart
│   │   ├── search/
│   │   │   └── search_service.dart
│   │   └── history/
│   │       └── play_history_service.dart
│   │
│   ├── providers/                 # 状态层
│   │   ├── audio_provider.dart
│   │   ├── playlist_provider.dart
│   │   ├── plugin_provider.dart
│   │   ├── theme_provider.dart
│   │   └── search_provider.dart
│   │
│   └── ui/                        # 视图层
│       ├── pages/
│       │   ├── home/              # 首页
│       │   ├── discover/          # 发现/搜索
│       │   ├── library/           # 我的
│       │   ├── player/            # 全屏播放器
│       │   │   └── widgets/
│       │   │       ├── album_art_view.dart
│       │   │       ├── playback_controls.dart
│       │   │       ├── progress_bar.dart
│       │   │       ├── lyrics_view.dart
│       │   │       ├── audio_visualizer.dart
│       │   │       └── player_sliver_bar.dart
│       │   ├── playlist_detail/   # 歌单详情
│       │   ├── settings/          # 设置
│       │   │   └── widgets/
│       │   │       ├── theme_selector.dart
│       │   │       ├── plugin_manager.dart
│       │   │       └── cache_settings.dart
│       │   └── splash/
│       │       └── splash_page.dart
│       └── shared/                # 共享组件
│           ├── mini_player.dart
│           ├── song_tile.dart
│           ├── playlist_card.dart
│           └── ai_float_ball.dart
│
├── test/                          # 测试
│   ├── unit/                      # 单元测试
│   ├── widget/                    # Widget 测试
│   └── integration/               # 集成测试
│
├── scripts/                       # 辅助脚本
│   ├── gen_icon.sh
│   └── analyze.sh
│
├── pubspec.yaml
├── analysis_options.yaml
├── l10n/
│   ├── app_zh.arb                 # 中文
│   └── app_en.arb                 # 英文
└── README.md
```

---

## 附录 A：推荐依赖汇总

| 包名 | 版本建议 | 用途 | 必选 |
|------|---------|------|------|
| flutter_riverpod | ^2.5.0 | 状态管理 | ✅ |
| freezed_annotation | ^2.4.0 | 不可变模型 | ✅ |
| json_annotation | ^4.9.0 | JSON 序列化 | ✅ |
| just_audio | ^0.9.36 | 音频播放 | ✅ |
| audio_service | ^0.18.12 | 后台播放 | ✅ |
| audio_session | ^0.1.19 | 音频会话 | ✅ |
| isar | ^3.1.0 | 本地数据库 | ✅ |
| isar_flutter_libs | ^3.1.0 | Isar 原生库 | ✅ |
| hive_flutter | ^1.1.0 | 配置存储 | ✅ |
| dio | ^5.4.0 | HTTP 请求 | ✅ |
| path_provider | ^2.1.0 | 文件路径 | ✅ |
| permission_handler | ^11.3.0 | 权限请求 | ✅ |
| extended_image | ^8.2.0 | 图片加载 | ✅ |
| shimmer | ^3.0.0 | 骨架屏 | ✅ |
| lottie | ^3.0.0 | 动画 | ✅ |
| flutter_animate | ^4.5.0 | 动画链 | ✅ |
| flutter_local_notifications | ^17.0.0 | 通知渠道 | ✅ |
| build_runner | ^2.4.0 | 代码生成 | dev |
| freezed | ^2.5.0 | 代码生成 | dev |
| json_serializable | ^6.8.0 | 代码生成 | dev |
| isar_generator | ^3.1.0 | 代码生成 | dev |

## 附录 B：Android 兼容性速查表

| Android 版本 | API 级别 | 注意事项 |
|-------------|---------|---------|
| Android 7.0 | 24 | 最低支持 |
| Android 8.0 | 26 | 通知渠道必须创建 |
| Android 10 | 29 | 后台启动 Activity 限制 |
| Android 12 | 31 | 精确闹钟权限、ForegroundService 类型 |
| Android 13 | 33 | POST_NOTIFICATIONS 动态权限 |
| Android 14 | 34 | 前台服务类型声明、媒体投递权限 |

## 附录 C：常见问题

1. **Q：如何获得音源？**
   A：应用本身不提供音源。用户需要安装第三方插件（`.cerm` 格式），或者自行编写符合规范的插件。

2. **Q：是否支持 iOS？**
   A：目前以 Android 为首要目标平台。iOS 需要解决后台播放限制（使用 `audio_service` 的 AVPlayer 实现）。

3. **Q：如何保证版权合规？**
   A：核心框架不包含任何版权内容。插件开发者需确保其插件遵守目标平台的用户协议与版权法规。

4. **Q：播放本地音乐文件？**
   A：可以开发本地文件扫描插件，通过 `permission_handler` 获取 `READ_MEDIA_AUDIO` 权限后，扫描设备上的音频文件。

5. **Q：如何处理 DRM 保护的音乐？**
   A：不支持 DRM 保护的内容。应用框架定位为合规播放器，不包含任何 DRM 解密能力。

6. **Q：应用被系统杀死后如何继续播放？**
   A：使用 `audio_service` 的前台服务模式，系统低内存时优先级较高。如果被系统强制杀死，无法自动恢复。

---

> **文档版本**：v1.1.0
> **最后更新**：2026 年 6 月
> **注**：本文档为完整开发规划，可根据实际开发进度调整优先级和范围。
