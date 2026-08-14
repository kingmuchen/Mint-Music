# MintMusic 歌词功能开发文档

> 基于 CeruMusic 源码分析，面向 Flutter/Android 端的完整歌词功能实现指南

---

## 一、CeruMusic 歌词系统架构总览

### 1.1 模块划分

CeruMusic 的歌词系统分为以下核心模块：

| 模块 | CeruMusic 源码位置 | 职责 |
|------|-------------------|------|
| 歌词数据模型 | `@applemusic-like-lyrics/core` (LyricLine/LyricWord 接口) | 定义歌词行、逐字词的统一数据结构 |
| 歌词解析器 | `@applemusic-like-lyrics/lyric` (parseLrc/parseYrc/parseQrc/parseTTML) | 将各平台原始歌词文本解析为统一模型 |
| LRC 格式转换 | `src/main/utils/lrcParser.ts` | 多种增强 LRC 格式互转、标准化 |
| 在线歌词获取 | `src/main/utils/musicSdk/{wy,tx,kg,kw,mg}/lyric.js` | 各平台 API 获取歌词 |
| 插件歌词获取 | `src/main/services/plugin/manager/CeruMusicPluginHost.ts` | 插件 getLyric 方法 |
| 本地嵌入歌词提取 | `src/main/events/localMusic.ts` | 从音频文件提取内嵌歌词 |
| 歌词状态管理 | `src/renderer/src/store/GlobalPlayStatus.ts` | 全局歌词加载、解析、翻译合并 |
| 歌词 UI 展示 | `src/renderer/src/components/Play/Lyric/LyricAdapter.vue` | 歌词滚动、高亮、逐字动画 |
| 桌面歌词窗口 | `src/main/windows/lyric-window.ts` + `DeskTopLyric.vue` | 独立置顶窗口显示歌词 |
| 桌面歌词桥接 | `src/renderer/src/utils/lyrics/desktopLyricBridge.ts` | 主窗口→桌面歌词窗口状态同步 |
| 歌词设置 | `LyricFontSettings.vue` + `DesktopLyricStyle.vue` | 字体、样式、动画等配置 |

### 1.2 数据流

```
在线音源API / 插件 / 本地文件
        ↓
  原始歌词文本 (lrc/yrc/qrc/krc/mrc/ttml)
        ↓
  格式解析器 (parseLrc/parseYrc/parseQrc/parseTTML)
        ↓
  统一 LyricLine[] 模型
        ↓
  翻译合并 (mergeTranslation)
        ↓
  数据清洗 (sanitizeLyricLines)
        ↓
  全局状态 (GlobalPlayStatus.player.lyrics)
        ↓
  UI 渲染 (LyricAdapter / LyricPlayer / DeskTopLyric)
```

---

## 二、歌词数据模型设计

### 2.1 CeruMusic 的核心接口

CeruMusic 使用 `@applemusic-like-lyrics` 库的接口：

```typescript
interface LyricLine {
  startTime: number   // 行开始时间（毫秒）
  endTime: number     // 行结束时间（毫秒）
  words: LyricWord[]  // 逐字/逐词列表
  translatedLyric?: string  // 翻译歌词
  romanLyric?: string       // 罗马音
  isBG?: boolean      // 是否为背景和声行
  isDuet?: boolean    // 是否为对唱行
}

interface LyricWord {
  word: string        // 文字内容
  startTime: number   // 词开始时间（毫秒）
  endTime: number     // 词结束时间（毫秒）
  romanWord?: string  // 逐字罗马音
}
```

**关键设计要点**：
- 每行有 `startTime` 和 `endTime`，支持精确的行级时间范围判定
- `words` 数组：当 `words.length > 1` 时为逐字歌词（YRC），`words.length === 1` 时为普通行歌词（LRC）
- 翻译和罗马音直接挂在行对象上，而非独立数组

### 2.2 Flutter 项目推荐模型

```dart
class LyricLine {
  final int startTimeMs;
  final int endTimeMs;
  final List<LyricWord> words;
  final String? translatedLyric;
  final String? romanLyric;
  final bool isBG;
  final bool isDuet;

  const LyricLine({
    required this.startTimeMs,
    required this.endTimeMs,
    required this.words,
    this.translatedLyric,
    this.romanLyric,
    this.isBG = false,
    this.isDuet = false,
  });

  bool get isYrc => words.length > 1;

  String get plainText => words.map((w) => w.word).join();
}

class LyricWord {
  final String word;
  final int startTimeMs;
  final int endTimeMs;
  final String? romanWord;

  const LyricWord({
    required this.word,
    required this.startTimeMs,
    required this.endTimeMs,
    this.romanWord,
  });

  int get durationMs => endTimeMs - startTimeMs;
}
```

### 2.3 与当前实现的差异

当前 Flutter 项目的 `LyricLine` 仅有：
- `timestamp` (Duration) — 无 endTime
- `text` (String) — 无 words 数组
- `translatedText` / `romanText` — 有但未与主歌词时间对齐

**需要重构为上述新模型**，这是所有后续功能的基础。

---

## 三、歌词格式与解析

### 3.1 支持的歌词格式

| 格式 | 平台 | 特征 | 示例 |
|------|------|------|------|
| **LRC** | 通用 | `[mm:ss.xx]text` | `[03:25.50]今天我 寒夜里看雪飘过` |
| **YRC** | 网易云 | `[startMs,duration](charStart,charDur,flag)char` | `[20550,3000](0,500,0)今(500,300,0)天...` |
| **QRC** | QQ音乐 | 类似YRC，需解密 | 加密的XML格式 |
| **KRC** | 酷狗 | 加密二进制，需zlib解压+XOR解密 | Base64编码的加密数据 |
| **MRC** | 咪咕 | `[startMs,duration](charStart,charDur)char` | 类似YRC但参数为2个 |
| **TTML** | Apple Music | XML格式，精确到毫秒的逐字时间 | AMLL TTML 数据库 |

### 3.2 LRC 解析（当前已实现，需增强）

当前实现仅支持标准 LRC，需要增强：

```dart
List<LyricLine> parseLrc(String lrcText, {String? tlyric, String? rlyric}) {
  // 1. 解析 offset 标签: [offset:+/-ms]
  // 2. 解析标准时间标签: [mm:ss.xx] 或 [mm:ss.xxx]
  // 3. 清除逐字标签: <mm:ss.xx>
  // 4. 构建翻译/罗马音映射（按时间戳对齐）
  // 5. 排序并计算 endTime（下一行 startTime - 1ms）
}
```

**增强点**：
- 支持 `[offset:xxx]` 全局偏移
- 自动计算 `endTime`（取下一行 startTime）
- 翻译对齐：容差 300ms 内的时间戳匹配

### 3.3 YRC 解析（网易云逐字歌词，需新增）

YRC 格式：`[行开始ms,行持续ms](字开始ms,字持续ms,标记)文字(字开始ms,字持续ms,标记)文字...`

```dart
List<LyricLine> parseYrc(String yrcText) {
  final lines = <LyricLine>[];
  final lineRegExp = RegExp(r'^\[(\d+),(\d+)\](.*)$');
  final wordRegExp = RegExp(r'\((\d+),(\d+),(\d+)\)');

  for (final line in yrcText.split('\n')) {
    final lineMatch = lineRegExp.firstMatch(line.trim());
    if (lineMatch == null) continue;

    final startTime = int.parse(lineMatch.group(1)!);
    final duration = int.parse(lineMatch.group(2)!);
    final endTime = startTime + duration;
    final content = lineMatch.group(3)!;

    final words = <LyricWord>[];
    var remaining = content;
    var currentOffset = startTime;

    while (remaining.isNotEmpty) {
      final wordMatch = wordRegExp.firstMatch(remaining);
      if (wordMatch == null) break;

      final wordStart = int.parse(wordMatch.group(1)!);
      final wordDuration = int.parse(wordMatch.group(2)!);
      final wordEnd = wordStart + wordDuration;

      final textBefore = remaining.substring(0, wordMatch.start);
      remaining = remaining.substring(wordMatch.end);

      if (textBefore.isNotEmpty) {
        words.add(LyricWord(
          word: textBefore,
          startTimeMs: currentOffset,
          endTimeMs: wordStart,
        ));
      }

      final wordText = remaining.isNotEmpty
          ? remaining.substring(0, remaining.startsWith('(') ? 0 : 1)
          : '';
      if (wordText.isNotEmpty) remaining = remaining.substring(wordText.length);

      words.add(LyricWord(
        word: wordText,
        startTimeMs: wordStart,
        endTimeMs: wordEnd,
      ));
      currentOffset = wordEnd;
    }

    if (words.isNotEmpty) {
      lines.add(LyricLine(
        startTimeMs: startTime,
        endTimeMs: endTime,
        words: words,
      ));
    }
  }

  return lines..sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));
}
```

### 3.4 QRC 解析（QQ音乐，需新增）

QRC 是 QQ 音乐的加密歌词格式。CeruMusic 的处理流程：

1. 通过 API 获取加密的 QRC 数据
2. 使用 `qrc-decrypt` 模块解密
3. 解密后格式类似 YRC：`[startMs,duration](charStart,charDuration,charFlag)text`
4. 使用 `parseQrc` 解析

**Flutter 实现建议**：在 `plugin/data/tx_music_source.dart` 中实现 QRC 解密逻辑，参考 CeruMusic 的 `src/main/utils/musicSdk/tx/qrc-decrypt`。

### 3.5 KRC 解析（酷狗，需新增）

KRC 是酷狗的加密歌词格式。CeruMusic 的处理流程：

1. 搜索歌词获取 ID 和 accessKey
2. 下载加密的 KRC 内容（Base64）
3. 跳过前4字节，XOR 解密（16字节密钥）
4. zlib 解压
5. 解析翻译标记 `[language:base64]`
6. 解析逐字时间标签

**解密密钥**：`[0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47, 0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e, 0x69]`

**Flutter 实现**：使用 `dart:io` 的 `ZLibDecoder` 和手动 XOR 操作。

### 3.6 TTML 解析（Apple Music 格式，可选增强）

CeruMusic 优先从 AMLL TTML 数据库获取 TTML 格式歌词：

```
https://amll-ttml-db.stevexmh.net/ncm/{songId}   (网易云)
https://amll-ttml-db.stevexmh.net/qq/{songId}     (QQ音乐)
```

TTML 是 XML 格式，包含精确的逐字时间信息。CeruMusic 使用 `@applemusic-like-lyrics/lyric` 的 `parseTTML` 解析。

**Flutter 实现**：使用 `xml` 包解析 TTML，或直接 HTTP 请求 AMLL 数据库。

### 3.7 格式转换工具（lrcParser.ts 对应）

CeruMusic 的 `lrcParser.ts` 提供了多种格式互转功能：

| 函数 | 功能 |
|------|------|
| `convertLrcFormat()` | 将增强格式（YRC新/旧格式）转换为标准 `<mm:ss.xxx>` 逐字标签 |
| `convertToStandardLrc()` | 将所有格式转为纯文本标准 LRC（去除逐字标签） |
| `normalizeLyricsToCrLyric()` | 将标准LRC/逐字LRC转为 `[startMs,duration](charStart,charDur,0)char` 格式 |

**Flutter 建议**：在 `lib/features/player/domain/services/` 下新建 `lyric_parser.dart`，统一管理所有解析和转换逻辑。

---

## 四、歌词获取策略

### 4.1 CeruMusic 的歌词获取优先级

```
1. TTML 数据库（仅 wy/tx 源，优先级最高，逐字最精确）
   ↓ 失败
2. 平台 SDK API（各平台 lyric.js）
   ↓ 失败
3. 插件 getLyric 方法
   ↓ 失败
4. 本地嵌入歌词（USLT/Vorbis）
```

### 4.2 各平台歌词 API 对接

#### 网易云（wy）
- **API**：`https://interface3.music.163.com/eapi/song/lyric/v1`（eapi 加密）
- **返回字段**：`lrc.lyric`, `tlyric.lyric`, `romalrc.lyric`, `yrc.lyric`, `ytlrc.lyric`, `yromalrc.lyric`
- **优先使用 yrc**（逐字），回退到 lrc（逐行）
- **翻译对齐**：`fixTimeLabel` 修正时间标签格式差异

#### QQ音乐（tx）
- **API**：`https://u.y.qq.com/cgi-bin/musicu.fcg`（需先获取 songId）
- **返回字段**：`lyric`（QRC加密）, `trans`（翻译QRC）, `roma`（罗马音QRC）
- **需要 QRC 解密**

#### 酷狗（kg）
- **流程**：先搜索 `http://lyrics.kugou.com/search` → 获取 ID + accessKey → 下载 `http://lyrics.kugou.com/download`
- **格式**：KRC（加密）或 LRC
- **需要 KRC 解密**

#### 酷我（kw）
- **API**：`http://newlyric.kuwo.cn/newlyric.lrc?{params}`
- **参数加密**：XOR 加密后 Base64
- **返回**：加密数据，需解密+解压
- **支持逐字歌词**（lrcx 格式）

#### 咪咕（mg）
- **优先 MRC**（逐字），回退 LRC
- **MRC 需解密**：`src/main/utils/musicSdk/mg/utils/mrc.ts`
- **翻译**：独立的 trcUrl

### 4.3 Flutter 项目对接建议

当前 Flutter 项目已有 `MusicSourceManager` 和各平台 `MusicSource`，需要在各 Source 中增加 `getLyric` 方法：

```dart
abstract class MusicSourceProvider {
  // ... 已有方法
  Future<LyricResult?> getLyric(Song song);
}

class LyricResult {
  final String? lrc;       // 标准 LRC
  final String? crlyric;   // 逐字歌词（YRC/QRC/KRC/MRC格式）
  final String? tlyric;    // 翻译歌词
  final String? rlyric;    // 罗马音歌词
}
```

---

## 五、歌词状态管理

### 5.1 CeruMusic 的状态管理

CeruMusic 在 `GlobalPlayStatus.ts` 中管理歌词状态：

```typescript
player.lyrics = {
  lines: LyricLine[],  // 解析后的歌词行
  trans?: string,       // 翻译原文
  source?: string       // 歌词来源
}
```

**歌词加载触发**：监听 `songId` 变化，自动加载歌词。

**竞态控制**：使用 `onCleanup` + `AbortController`，切换歌曲时取消上一次请求。

**数据清洗**（`sanitizeLyricLines`）：
- 修正 `startTime < 0` 的行
- 修正 `endTime <= startTime` 的行（默认 3000ms 持续时间）
- 修正 word 的时间重叠
- 按 startTime 排序

### 5.2 Flutter 项目重构建议

重构 `LyricController`：

```dart
class LyricController extends StateNotifier<LyricState> {
  final MusicSourceManager _musicSourceManager;
  String? _activeSongId;
  int _requestId = 0; // 竞态控制

  Future<void> loadLyrics(Song? song) async {
    if (song == null) {
      state = const LyricState();
      return;
    }

    final requestId = ++_requestId;

    state = LyricState(isLoading: true, currentSongId: song.id);

    try {
      List<LyricLine>? parsedLines;

      // 1. 尝试 TTML 数据库（wy/tx）
      if (song.source == 'wy' || song.source == 'tx') {
        parsedLines = await _tryFetchTtml(song);
      }

      // 2. 竞态检查
      if (requestId != _requestId) return;

      // 3. 回退到平台 SDK / 插件
      parsedLines ??= await _fetchFromSource(song);

      if (requestId != _requestId) return;

      // 4. 回退到本地嵌入歌词
      if (parsedLines == null && song.isLocal) {
        parsedLines = await _extractEmbedded(song);
      }

      if (requestId != _requestId) return;

      // 5. 数据清洗
      if (parsedLines != null) {
        parsedLines = sanitizeLyricLines(parsedLines);
      }

      state = LyricState(
        lines: parsedLines ?? [],
        currentSongId: song.id,
      );
    } catch (e) {
      if (requestId != _requestId) return;
      state = LyricState(error: '加载歌词失败', currentSongId: song.id);
    }
  }
}
```

### 5.3 翻译合并逻辑

CeruMusic 的翻译合并算法（`mergeTranslation`）：

1. 解析翻译歌词为 `LyricLine[]`
2. 按 `startTime` 排序
3. **锚点匹配**：找到第一行翻译与第一行原文的时间差在容差内（300ms 或行持续时间的40%）
4. 从锚点开始，逐行对齐原文和翻译
5. 跳过翻译内容为 `//` 的行（纯音乐标记）

```dart
List<LyricLine> mergeTranslation(List<LyricLine> base, String? tlyric) {
  if (tlyric == null || tlyric.isEmpty || base.isEmpty) return base;

  final translated = parseLrc(tlyric);
  if (translated.isEmpty) return base;

  final tolerance = 300;
  final ratioTolerance = 0.4;

  // 找锚点
  int? anchorIndex;
  var bestDiff = double.infinity;
  for (int i = 0; i < translated.length; i++) {
    final firstDuration = (base[0].endTimeMs - base[0].startTimeMs).abs();
    final firstTol = min(tolerance, firstDuration * ratioTolerance);
    final diff = (translated[i].startTimeMs - base[0].startTimeMs).abs();
    if (diff <= firstTol && diff < bestDiff) {
      bestDiff = diff;
      anchorIndex = i;
    }
  }

  if (anchorIndex != null) {
    var j = anchorIndex;
    for (int i = 0; i < base.length && j < translated.length; i++, j++) {
      final tranText = translated[j].plainText;
      if (tranText == '//' || base[i].plainText.isEmpty) continue;
      if (tranText.isNotEmpty) {
        base[i] = base[i].copyWith(translatedLyric: tranText);
      }
    }
  }

  return base;
}
```

---

## 六、歌词 UI 展示

### 6.1 CeruMusic 的 LyricAdapter 核心逻辑

#### 6.1.1 当前行判定

```typescript
// 逐字歌词（YRC）：使用 startTime/endTime 范围判定
if (hasYrc) {
  for (let i = 0; i < lyrics.length; i++) {
    if (currentTime >= lyrics[i].startTime && currentTime < lyrics[i].endTime) {
      activeIndices.push(i);
    }
  }
  // 最多保留最近3个活跃行
  return activeIndices.length > 3 ? activeIndices.slice(-3) : activeIndices;
}

// 普通歌词（LRC）：使用 startTime + 300ms 前瞻
const playSeek = currentTime + 300;
const idx = lyrics.findIndex(v => v.startTime > playSeek);
return idx > 0 ? [idx - 1] : [];
```

**关键**：YRC 模式下可能同时有多行活跃（因为行间可能有重叠），LRC 模式用 300ms 前瞻避免提前切换。

#### 6.1.2 平滑滚动

```typescript
const smoothScrollTo = (container, targetY, duration = 300) => {
  const startY = container.scrollTop;
  const diff = targetY - startY;
  const startTime = performance.now();

  const step = (currentTime) => {
    const elapsed = currentTime - startTime;
    const progress = Math.min(elapsed / duration, 1);
    // easeInOutQuad 缓动
    const eased = progress < 0.5
      ? 2 * progress * progress
      : 1 - Math.pow(-2 * progress + 2, 2) / 2;
    container.scrollTop = startY + diff * eased;
    if (progress < 1) requestAnimationFrame(step);
  };

  requestAnimationFrame(step);
};
```

**滚动目标计算**：
```
targetY = elementTop - (containerHeight - elementHeight) * alignPosition
```
其中 `alignPosition` 默认 0.5（居中）。

#### 6.1.3 用户滚动检测

```typescript
const USER_SCROLL_TIMEOUT = 3000; // 3秒

const handleUserScroll = () => {
  userScrolling.value = true;
  clearTimeout(userScrollTimeoutId);
  userScrollTimeoutId = setTimeout(() => {
    userScrolling.value = false;
    lyricsScroll(scrollTargetIndex.value);
  }, USER_SCROLL_TIMEOUT);
};
```

用户手动滚动时暂停自动滚动，3秒无操作后恢复。

#### 6.1.4 逐字歌词动画（YRC）

**CSS mask 渐变遮罩**：实现逐字填充效果

```css
.yrc-word {
  mask-image: linear-gradient(
    to right,
    rgba(0, 0, 0, var(--yrc-bright-alpha)) 45.45%,
    rgba(0, 0, 0, var(--yrc-dark-alpha)) 54.55%
  );
  mask-size: 220% 100%;
  mask-repeat: no-repeat;
  -webkit-mask-position-x: var(--yrc-mask-x);
}
```

**maskX 计算**：
```typescript
const progress = (currentTime - word.startTime) / (word.endTime - word.startTime);
const maskX = `${(1 - progress) * 100}%`;
```

**逐字上浮动画**：
- 正在唱的字：向上偏移 + 轻微放大
- 唱完的字：回落到原位 + 弹性缓动
- 动画幅度与字时长成正比

#### 6.1.5 模糊效果（Apple Music 风格）

```typescript
const getLyricLineStyle = (index: number) => {
  const dist = Math.abs(activeIdx - index);
  const blurPx = dist === 0 ? 0 : Math.min(1.2 + Math.pow(dist, 0.7) * 1.5, 8);
  return { filter: isOn ? 'blur(0)' : `blur(${blurPx}px)` };
};
```

非活跃行按距离递增模糊，最大 8px。

#### 6.1.6 行点击跳转

点击歌词行时，seek 到该行的 `startTime`。

### 6.2 Flutter 实现方案

#### 6.2.1 歌词滚动组件

```dart
class LyricScrollView extends StatefulWidget {
  final List<LyricLine> lines;
  final int currentTimeMs;
  final bool isPlaying;
  final double alignPosition; // 0.5 = 居中
  final bool enableBlur;
  final bool enableScale;
  final VoidCallback? onUserScrollStart;
  final VoidCallback? onUserScrollEnd;
  final ValueChanged<int>? onLineClick;

  const LyricScrollView({...});
}
```

**核心实现要点**：

1. **ScrollController + AnimationController**：使用 `ScrollController` 控制滚动位置，`AnimationController` 实现平滑滚动动画

2. **当前行判定**：根据 `currentTimeMs` 和歌词类型（YRC/LRC）计算活跃行索引

3. **平滑滚动**：使用 `ScrollController.animateTo()` 或自定义 `AnimationController` 实现缓动

4. **用户滚动检测**：监听 `ScrollNotification`，设置 3 秒定时器

5. **行点击**：`GestureDetector` + `onTap` 回调 seek

#### 6.2.2 逐字歌词渲染

Flutter 中实现逐字填充效果有两种方案：

**方案 A：ShaderMask + Linear Gradient（推荐）**

```dart
Widget _buildYrcWord(LyricWord word, int currentTimeMs) {
  final progress = (currentTimeMs - word.startTimeMs)
      .clamp(0, word.durationMs) / word.durationMs;

  return ShaderMask(
    shaderCallback: (Rect bounds) {
      return LinearGradient(
        colors: [activeColor, inactiveColor],
        stops: [progress, progress],
      ).createShader(bounds);
    },
    blendMode: BlendMode.srcIn,
    child: Text(word.word, style: lyricTextStyle),
  );
}
```

**方案 B：CustomPainter + Clip**

使用 `CustomPaint` 绘制文字，通过 `canvas.clipRect` 控制填充区域。

#### 6.2.3 模糊效果

```dart
Widget _buildLyricLine(int index, LyricLine line, bool isActive, int activeIdx) {
  if (!enableBlur) return child;

  final dist = (index - activeIdx).abs();
  final blurPx = dist == 0 ? 0.0 : min(1.2 + pow(dist, 0.7) * 1.5, 8.0);

  return ImageFiltered(
    imageFilter: ui.ImageFilter.blur(sigmaX: blurPx, sigmaY: blurPx),
    child: child,
  );
}
```

> **注意**：`ImageFiltered` 在低端设备上可能有性能问题，建议提供开关。

#### 6.2.4 翻译和罗马音显示

```dart
Widget _buildLineContent(LyricLine line, bool isActive) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildMainText(line, isActive),
      if (line.translatedLyric != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            line.translatedLyric!,
            style: TextStyle(
              fontSize: mainFontSize * 0.52,
              color: isActive ? activeColor.withOpacity(0.6) : inactiveColor,
            ),
          ),
        ),
      if (line.romanLyric != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            line.romanLyric!,
            style: TextStyle(
              fontSize: mainFontSize * 0.73,
              color: isActive ? activeColor.withOpacity(0.5) : inactiveColor,
            ),
          ),
        ),
    ],
  );
}
```

---

## 七、歌词与播放器同步

### 7.1 CeruMusic 的同步机制

CeruMusic 使用两种同步方式：

1. **主窗口歌词**：直接读取 `ControlAudio.Audio.currentTime`（秒），乘以 1000 转为毫秒
2. **桌面歌词窗口**：通过 `desktopLyricBridge.ts` 的 RAF 循环推送

```typescript
// desktopLyricBridge.ts 的 RAF 循环
const loop = () => {
  const ms = Math.round(audio.currentTime * 1000);
  const idx = computeLyricIndex(ms, currentLines);

  // 推送进度（用于逐字判定）
  ipcRenderer.send('play-lyric-progress', { index: idx, progress, currentMs: ms });

  // 行变化时推送 index
  if (idx !== lastIndex) {
    ipcRenderer.send('play-lyric-index', idx);
  }

  requestAnimationFrame(loop);
};
```

### 7.2 Flutter 同步方案

Flutter 使用 `just_audio` 的 `StreamBuilder` 或 `PositionStream`：

```dart
// 在 LyricPage/FullPlayerPage 中监听位置流
StreamBuilder<Duration>(
  stream: audioPlayer.positionStream,
  builder: (context, snapshot) {
    final position = snapshot.data ?? Duration.zero;
    final currentMs = position.inMilliseconds;

    return LyricScrollView(
      lines: lyricState.lines,
      currentTimeMs: currentMs,
      isPlaying: audioPlayer.playing,
    );
  },
);
```

**优化建议**：
- 使用 `audioPlayer.positionStream` 而非定时器轮询
- 逐字动画需要高频率更新（~60fps），可使用 `Stream.periodic` + `audioPlayer.position` 组合
- 桌面歌词不需要（Android 端），但可考虑悬浮窗方案（见第八节）

---

## 八、Android 悬浮歌词（可选，对应桌面歌词）

### 8.1 CeruMusic 桌面歌词功能

CeruMusic 的桌面歌词是一个独立的 Electron BrowserWindow：
- 始终置顶（`alwaysOnTop: 'screen-saver'`）
- 透明背景
- 可拖动、可调整大小
- 可锁定（鼠标穿透）
- 可配置字体、颜色、动画等

### 8.2 Android 悬浮窗歌词方案

Android 上实现类似功能需要：

1. **权限**：`SYSTEM_ALERT_WINDOW`（悬浮窗权限）
2. **实现方式**：使用 Android 的 `WindowManager` 添加悬浮 View
3. **Flutter 集成**：通过 `MethodChannel` 调用原生代码

**推荐实现路径**：

```
lib/features/player/platform/
  ├── floating_lyric_service.dart   # Flutter 端 MethodChannel 接口
  └── floating_lyric_controller.dart # 歌词数据推送

android/app/src/main/kotlin/
  └── FloatingLyricService.kt       # 原生悬浮窗实现
```

**优先级**：低。Android 悬浮歌词属于增强功能，建议在核心歌词功能完成后再实现。

---

## 九、歌词设置

### 9.1 CeruMusic 的歌词设置项

| 设置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| 歌词字体 | string | PingFangSC-Semibold | 支持多选，逗号分隔 |
| 字体倍率 | number | 1.0 | 0.1 ~ 2.0 |
| 字重 | number | 600 | 100 ~ 900 |
| 沉浸色歌词 | bool | true | 根据封面颜色调整歌词色 |
| 模糊歌词 | bool | false | Apple Music 风格模糊 |
| 跳动歌词 | bool | true | 行切换时的动画 |
| AMLL渲染器 | bool | true | 使用 AppleMusicLike 渲染器 |
| 桌面歌词字号 | number | 30 | 12 ~ 96 |
| 桌面歌词主色 | string | #73BCFC | |
| 桌面歌词阴影色 | string | rgba(255,255,255,0.5) | |
| 桌面歌词对齐 | string | center | left/center/right/both |
| 逐字歌词 | bool | true | |
| 显示翻译 | bool | false | |
| 双行显示 | bool | true | |
| 动画 | bool | true | |
| 文字背景遮罩 | bool | false | |

### 9.2 Flutter 项目建议设置项

**第一阶段（核心）**：
- 歌词字号
- 歌词字重
- 显示翻译开关
- 显示罗马音开关
- 沉浸色歌词开关

**第二阶段（增强）**：
- 模糊效果开关
- 逐字动画开关
- 歌词对齐方式
- 歌词字体选择

**第三阶段（悬浮歌词）**：
- 悬浮歌词开关
- 悬浮歌词字号
- 悬浮歌词颜色

---

## 十、实现计划与优先级

### Phase 1：数据层重构（基础）

| 任务 | 文件 | 说明 |
|------|------|------|
| 重构 LyricLine/LyricWord 模型 | `domain/models/lyric_line.dart` | 新增 endTimeMs, words, isYrc 等 |
| 重构 LRC 解析器 | `domain/services/lyric_parser.dart` | 支持 offset, 自动 endTime, 翻译对齐 |
| 新增 YRC 解析器 | `domain/services/yrc_parser.dart` | 网易云逐字格式 |
| 新增 QRC 解析器 | `domain/services/qrc_parser.dart` | QQ音乐加密格式 |
| 新增 KRC 解析器 | `domain/services/krc_parser.dart` | 酷狗加密格式 |
| 新增 MRC 解析器 | `domain/services/mrc_parser.dart` | 咪咕格式 |
| 重构 LyricController | `application/lyric_controller.dart` | 竞态控制, 翻译合并, 数据清洗 |
| 各平台 Source 增加 getLyric | `plugin/data/*.dart` | 返回 LyricResult |

### Phase 2：UI 层重构（核心展示）

| 任务 | 文件 | 说明 |
|------|------|------|
| 新建 LyricScrollView | `presentation/widgets/lyric_scroll_view.dart` | 平滑滚动, 用户滚动检测 |
| 新建 YrcWordRenderer | `presentation/widgets/yrc_word_renderer.dart` | 逐字填充动画 |
| 重构 LyricPage | `presentation/lyric_page.dart` | 使用新组件, 支持翻译/罗马音 |
| 重构 FullPlayerPage 歌词区 | `presentation/full_player_page.dart` | 集成新歌词组件 |
| 行点击跳转 | 上述组件内 | 点击歌词行 seek |
| 模糊效果 | 上述组件内 | 可选的 Apple Music 风格模糊 |

### Phase 3：增强功能

| 任务 | 文件 | 说明 |
|------|------|------|
| TTML 数据库获取 | `domain/services/ttml_service.dart` | 从 AMLL 数据库获取精确逐字歌词 |
| 歌词设置页面 | `settings/presentation/lyric_settings_page.dart` | 字体、字号、翻译等设置 |
| 沉浸色歌词 | 上述组件内 | 根据封面主色调整歌词颜色 |
| 删除旧的 LyricDisplay | `presentation/widgets/lyric_display.dart` | 用新组件替代 |

### Phase 4：悬浮歌词（可选）

| 任务 | 文件 | 说明 |
|------|------|------|
| 悬浮窗原生实现 | `platform/floating_lyric_*.kt` | Android WindowManager |
| Flutter MethodChannel | `platform/floating_lyric_service.dart` | 桥接 |
| 悬浮歌词 UI | - | 简化版歌词显示 |
| 悬浮歌词设置 | 设置页内 | 开关、字号、颜色 |

---

## 十一、关键源码索引

| 功能 | CeruMusic 源码路径 |
|------|-------------------|
| LRC 格式转换 | `src/main/utils/lrcParser.ts` |
| 歌词 UI 组件 | `src/renderer/src/components/Play/Lyric/LyricAdapter.vue` |
| 歌词 IPC 事件 | `src/main/events/lyric.ts` |
| 桌面歌词窗口 | `src/main/windows/lyric-window.ts` |
| 桌面歌词 UI | `src/renderer/src/views/DeskTopLyric/DeskTopLyric.vue` |
| 桌面歌词桥接 | `src/renderer/src/utils/lyrics/desktopLyricBridge.ts` |
| 全局播放状态 | `src/renderer/src/store/GlobalPlayStatus.ts` |
| 播放设置 | `src/renderer/src/store/playSetting.ts` |
| 歌词字体设置 | `src/renderer/src/components/Settings/LyricFontSettings.vue` |
| 桌面歌词样式 | `src/renderer/src/components/Settings/DesktopLyricStyle.vue` |
| 全屏播放页 | `src/renderer/src/components/Play/FullPlay.vue` |
| 网易云歌词 | `src/main/utils/musicSdk/wy/lyric.js` |
| QQ歌词 | `src/main/utils/musicSdk/tx/lyric.js` |
| 酷狗歌词 | `src/main/utils/musicSdk/kg/lyric.js` |
| 酷我歌词 | `src/main/utils/musicSdk/kw/lyric.js` |
| 咪咕歌词 | `src/main/utils/musicSdk/mg/lyric.js` |
| 酷狗KRC解密 | `src/common/utils/lyricUtils/kg.js` |
| 插件歌词 | `src/main/services/plugin/manager/CeruMusicPluginHost.ts` |
| 歌词配置类型 | `src/common/types/config.ts` |
| 音乐SDK类型 | `src/main/services/musicSdk/type.ts` |

---

## 十二、当前 Flutter 项目差距分析

| 功能 | CeruMusic | 当前 Flutter | 差距 |
|------|-----------|-------------|------|
| LRC 解析 | ✅ 完整（offset, 翻译对齐） | ⚠️ 基础（无 offset, 翻译未对齐） | 中 |
| YRC 解析 | ✅ | ❌ | 高 |
| QRC 解析 | ✅ | ❌ | 高 |
| KRC 解析 | ✅ | ❌ | 高 |
| MRC 解析 | ✅ | ❌ | 中 |
| TTML 支持 | ✅ | ❌ | 中 |
| 逐字动画 | ✅ mask 渐变 | ❌ | 高 |
| 平滑滚动 | ✅ 自定义缓动 | ⚠️ animateTo | 低 |
| 用户滚动检测 | ✅ 3秒恢复 | ❌ | 中 |
| 模糊效果 | ✅ 非线性模糊 | ❌ | 中 |
| 翻译显示 | ✅ | ⚠️ 有字段但未对齐 | 中 |
| 罗马音显示 | ✅ | ⚠️ 有字段但未对齐 | 中 |
| 行点击跳转 | ✅ | ❌ | 低 |
| 沉浸色歌词 | ✅ 封面取色 | ❌ | 中 |
| 歌词设置 | ✅ 完整 | ❌ | 中 |
| 桌面/悬浮歌词 | ✅ | ❌ | 低（Android可选） |
| 数据模型 | ✅ LyricLine+LyricWord | ⚠️ 简单 LyricLine | 高 |
| 竞态控制 | ✅ AbortController | ❌ | 中 |
| 数据清洗 | ✅ sanitizeLyricLines | ❌ | 中 |
| 本地嵌入歌词 | ✅ | ✅ | 无 |
