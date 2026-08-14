# CeruMusic Android 复刻开发记录

## 当前修复记录

### 插件歌词兼容

- 插件歌词优先通过插件系统获取，失败后再回退到内建音源。
- `module.exports.getLyric` 返回空时，会继续尝试洛雪音源常用的 `requestHandler` 歌词动作。
- 歌词结果支持字符串、`lyric`、`lrc`、`text`、`content`、`raw`、`data` 以及嵌套对象格式。

### 发现页热门歌单

- 热门歌单先调用各平台自身热门接口。
- 如果平台热门接口为空，自动回退到分类歌单的热门排序。
- 如果分类热门仍为空，继续尝试热门标签下的歌单。
- 发现页当前实际走 `getCategoryPlaylists(sortId: 'hot')`，因此同样补充了分类入口兜底。

### 搜索建议

- 搜索提示框不再在“全部”平台时固定请求网易云。
- “全部”平台会聚合多个可搜索源的建议，并按文本去重。
- 插件建议先尝试插件搜索导出方法，再尝试洛雪音源 `requestHandler` 搜索动作，最后回退内建源建议。

## 2026-05-25 追加修复

- tx 歌词：修复 QRC 逐字歌词正则捕获组错误，并加入 `crypt=0` Base64 标准歌词回退，避免 QRC 解密失败时歌词为空。
- 酷狗歌单：热门歌单接口域名改为 CeruMusic 当前使用的 `www2.kugou.kugou.com`。
- 咪咕歌单：热门歌单改用新版歌单广场接口 `playlist-square-recommend`，并递归解析歌单节点。
- 搜索建议：修复酷狗建议接口返回结构解析；当建议接口为空时，会回退到真实搜索结果生成建议。

## 验证重点

- 使用同一插件搜索并播放 `kw`、`tx` 歌曲，确认歌词页可显示歌词。
- 发现页切换到酷狗、酷我、QQ、咪咕后，确认热门歌单不为空。
- 搜索页输入关键词时，确认搜索提示框展示建议；选择“全部”平台时应能聚合多个源。
## 2026-05-25 深度修复补充

- QQ 音乐签名接口统一修正为 `https://u.y.qq.com/cgi-bin/musicu.fcg`，避免 `musics.fcg` 拼写错误导致歌曲详情、播放地址、排行榜与歌词兜底链路失败。
- QQ 歌词在 QRC 接口异常、返回码异常或逐字歌词解析为空时，继续回退到 `crypt=0` 的标准 Base64 LRC 歌词；数字 songId 不再错误传入 `songMID`。
- QQ 热门歌单兼容 `song_ids` 返回字符串或列表的两种结构，避免类型转换异常导致整批歌单为空。
- 酷我热门歌单兼容 `listencnt`、`total` 等字段返回字符串的情况，避免播放量/歌曲数类型异常导致页面为空。
- 排行榜对齐 CeruMusic 的稳定策略：酷狗改用 v5 榜单接口并保留静态榜单兜底；酷我、QQ、咪咕在上游接口为空或失效时返回 CeruMusic 常用榜单入口。
- 发现页平台选择弹窗改为根导航弹出，并为迷你播放器预留底部安全间距，避免“咪咕”选项被遮挡。
## 2026-05-26 tx 歌词与非网易发现页深度修复

- 对照 CeruMusic `tx/lyric.js` 后调整歌词链路：QQ 音乐优先走内建 `GetPlayLyricInfo` + QRC/标准 LRC 解析，避免插件返回非标准原始歌词时阻断内建 tx 歌词解析。
- 对照 CeruMusic `tx/leaderboard.js` 后调整 QQ 榜单详情请求体，使用 `toplist.GetDetail`、`topid`、`num` 的结构获取榜单歌曲。
- 发现页普通歌单详情增加排行榜详情兜底：非网易平台卡片若普通歌单详情为空，会自动尝试对应平台 `getLeaderboardDetail`，解决排行榜卡片点击后“歌单未找到/无歌曲”的问题。
- 对照 CeruMusic `kg/songList.js` 后为酷狗歌单详情增加 HTML `global.data` 解析兜底，解决酷狗热门歌单只有封面、详情无歌曲的问题。
- 对照 CeruMusic `kg/leaderboard.js` 后修正酷狗榜单详情接口为 `mobilecdnbj.kugou.com/api/v3/rank/song`，按 `data.info` 解析歌曲。
- 对照 CeruMusic `mg/songList.js` 后将咪咕歌单详情改为 `MIGUM3.0/resource/playlist/song/v2.0` 与 `resource/playlist/v2.0`，解决咪咕歌单卡片详情无歌曲的问题。
- 对照 CeruMusic `mg/leaderboard.js` 后补齐咪咕榜单详情 `querycontentbyId.do?columnId=...`，按 `columnInfo.contents[].objectInfo` 解析歌曲。
- QQ 热门歌单/分类歌单解析兼容接口返回字符串 JSON、`creator_info`/`creator` 非 Map、`song_ids` 非 List 等情况，避免单个字段类型变化导致整页“暂无歌单数据”。
- 对照 CeruMusic `kw/songList.js` 后调整酷我歌单详情 nplserver 参数，补齐 `pn/rn/vipver/newver`；digest 13 不再直接返回空，改为继续尝试标准歌单详情。
- 对照 CeruMusic `kw/leaderboard.js` 的旧接口注释，将酷我榜单详情 `data=bang` 修正为 `data=content`，为空时回退到 nplserver 榜单详情。
# 2026-05-26 非网易发现页与 tx 插件歌词再修复

- 酷狗歌单详情对齐 CeruMusic：HTML 歌单只作为入口，歌曲列表再通过 `gateway.kugou.com/v2/album_audio/audio` 批量补全，修复歌曲封面缺失与时长毫秒/秒混用问题。
- 酷狗排行榜改用 CeruMusic 的 `mobilecdnbj.kugou.com/api/v3/rank/song` 详情接口，并修正榜单列表 `errcode/status` 判断。
- 酷我热门歌单页码改为 CeruMusic 的 `pn=1`，并兼容字符串 JSON；酷我排行榜新增 WBD 加密参数与 AES 解密链路，优先走 `wbd.kuwo.cn/api/bd/bang/bang_info`。
- QQ 排行榜详情补齐 CeruMusic 的 period 获取逻辑，从 `wk_v15/top.html` 解析榜单期数后再请求 `GetDetail`。
- 插件 tx 歌词链路保留插件搜索返回的 `songId/songid`，通过 `MusicInfoForPlugin.songId` 回传给插件，并让内建 QQ 歌词优先使用数值 songId。

## 2026-06-02 AMLL / CeruMusic 逐字歌词实现

- 对照 CeruMusic `LyricAdapter.vue` 与 AMLL `LyricLine` / `LyricWord` 数据结构，Flutter 侧继续使用统一的 `LyricLine.words`、`translatedLyric`、`romanLyric`、`startTimeMs`、`endTimeMs` 模型承载逐字歌词。
- 歌词解析器补齐 CeruMusic 常见的逐字歌词格式：YRC、QRC、KRC、MRC、LRCX，并支持从 QQ/CeruMusic XML 中提取 `LyricContent` 后再解析。
- 修正 YRC/QRC/KRC/MRC 行内逐字时间轴：这些格式的词起点通常是相对当前行的时间，需要转换为播放绝对时间后再交给播放器渲染。
- 歌词页渲染对齐 AMLL 的核心体验：当前行居中滚动、用户手动滚动后 3 秒暂停自动滚动、逐字亮色遮罩推进、当前词轻微上浮放大、翻译和罗马音跟随当前行变亮。
- 全屏播放器歌词页和独立歌词页共享同一个 `LyricScrollView`，因此逐字歌词、普通 LRC、翻译、罗马音、拖动跳转行为保持一致。

## 2026-06-02 逐字歌词动画性能修复

- 对照 CeruMusic `LyricAdapter.vue`：逐字歌词的核心动画为当前行 `transform/opacity/filter` 过渡、词级 mask 推进、词级 translateY/scale 过渡，滚动使用 500ms easeInOutQuad，用户滚动后 3 秒恢复自动居中。
- 对照 AMLL `lyric-player`：歌词行需要隔离绘制区域，避免播放进度变化导致整棵歌词列表重排；Web 侧依赖 `will-change`、`contain`、`content-visibility` 与合成层，本项目 Flutter 侧改用 `RepaintBoundary + CustomPainter` 对应。
- 播放进度源当前有 200ms 节流，直接用外部 position 会造成逐字高亮跳动；歌词组件内部新增 60fps `Ticker` 平滑时钟，只在当前行变化时触发列表重建。
- 当前行逐字绘制改为画布级实现：每个词预布局 TextPainter，帧更新时只绘制暗字与按进度裁剪的亮字，不再为每个词创建 `AnimatedSlide`、`AnimatedScale`、`Stack`、双层 `Text`。
- 未来词默认下沉 `0.16em`、演唱词按 CeruMusic 的时长因子放大/上浮、完成后 2 秒回落，尽量保持 CeruMusic 的运动参数。

## 2026-06-02 逐字歌词未启动修复

- 对照 SPICaMusic：歌词解析入口先判断是否包含 `](` 等逐字结构，逐字解析失败才回退普通 LRC；播放页使用帧级时间驱动，而不是只依赖低频进度回调。
- 插件歌词结果不再压扁为单一 `lrc` 字符串，新增完整 `LyricResult` 归一化链路，优先保留 `crlyric/lxlyric/yrc/krc/qrc/mrc/lrcx/lyricx/ttml/wordLyric` 等逐字字段，同时保留 `tlyric/rlyric`。
- `LyricController` 现在会同时检查 `crlyric` 和 `lrc` 候选内容，优先选择能解析出 `words.length > 1` 的逐字歌词；只有没有逐字结果时才使用普通 LRC。
- `lyric_parser` 增强支持两段式 YRC `(start,duration)`、增强 LRC `<mm:ss.xxx>` 逐字标签、TTML 自动识别、QQ/CeruMusic `LyricContent` XML 提取。

## 2026-06-02 逐字歌词流畅度与 YRC/QRC 启动修复

- 歌词视图内部时钟不再在播放中被外部低频进度回调硬重置；小于 450ms 的漂移会按比例平滑追帧，避免逐字高亮每 200ms 抖动。
- 逐字歌词行增加 TextPainter 布局缓存，当前行逐帧只触发 CustomPainter 重绘；播放逐字歌词时暂停非当前行 blur 滤镜，降低 raster 压力。
- 网易云歌词优先请求 `/lyric/new` 并带 YRC 相关参数，若拿到 `yrc.lyric` 则优先作为 `crlyric` 返回，失败再回退 `/lyric`。
- QQ 歌词支持 `qrc` 与 `lyric` 两种加密字段；修复 QRC 转内部逐字格式时“时间标签与文字错位”的问题，避免整行只解析成一个词导致 `hasYrc=false`。
- QQ 内置源只把普通 LRC 当作兜底；如果插件或数字 songId 能返回 QRC，不再被普通歌词提前截断。

### 本次验证

- `dart run tool/lyric_word_probe.dart` 临时探针已验证 QRC/YRC 样例均可解析为多词逐字行，`hasYrc=true`，探针文件已删除。
- `flutter analyze --no-pub` 针对歌词视图、歌词解析器、音源管理、网易云源、QQ 源运行完成，无编译错误；剩余为项目既有 `print`、死代码、风格类提示。

### 追加说明

- `parseYrc` 现同时兼容 `[start,duration](wordStart,wordDuration,0)字` 与 `[mm:ss.xxx](wordStart,wordDuration,0)字` 两类逐字行，避免 QQ/CeruMusic 兼容格式被识别为逐字后又解析为空。
- QQ 内置 QRC 转换输出已改为 `[start,duration]` 行时间轴，插件返回的兼容格式仍由解析器兜底支持。

## 2026-06-05 对齐 CeruMusic 歌词获取策略

### 核心改动

1. **TTML 时间截断移除** (`lyric_controller.dart`)：移除了 `firstLineTime > 30000` 的截断检查。对齐 CeruMusic：TTML 可用则直接使用，不设时间截断。歌曲前奏长导致第一句在 66s 属于正常情况。

2. **插件优先于内建源** (`music_source_manager.dart`)：`getLyricResult` 和 `getLyric` 的优先级改为**插件优先**，对齐 CeruMusic 的插件替换策略。当插件加载后，CeruMusic 内建 SDK 不再执行；我们同样先尝试插件，失败再回退内建源。

3. **YRC 转换失败处理** (`netease_music_source.dart`)：`_convertNeteaseYrc` 返回 null 时不再传递原始 JSON-lines 格式（`parseLyricAuto` 无法识别），而是直接丢弃 `crlyric`，避免静默回退到 LRC 导致逐字动画缺失。

### 修复原因总结

CeruMusic wy 源不缺失开头逐字歌词的原因：
- CeruMusic 内建 wy SDK 直接调用 NetEase 官方 EAPI（`eapi/song/lyric/v1`），不走代理
- 插件加载后**完全替代**内建 SDK，插件在 JS 引擎中直接调 NetEase 官方接口
- 我们的代理（`netease-cloud-music-api`）可能未正确透传 `yrc.lyric`
- 之前 `getLyricResult` 先问代理（无 crlyric），插件结果即使有 crlyric 也可能因执行顺序或转换失败未被采用
## 2026-06-21 洛雪音源适配对齐 Sollin-Music

本轮已将洛雪音源宿主契约向 Sollin-Music 对齐：`lx.request` 支持回调签名，`lx.send/lx.on/lx.utils` 补齐，插件搜索结果的平台特定字段会保存到 `Song.lx` 并在播放地址、歌词、封面请求时回传。详细维护说明见 `docs/lx_source_adaptation.md`。
