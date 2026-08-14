import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../domain/models/lyric_line.dart';

class AmllLyricPlayer extends StatefulWidget {
  final List<LyricLine> lines;
  final int currentTimeMs;
  final bool isPlaying;
  final String fontFamily;
  final double fontSizeRate;
  final int fontWeight;
  final bool showTranslation;
  final bool showRoman;
  final bool enableBlur;
  final bool enableScale;
  final bool enableJumpLyric;
  final bool centerAlign;
  final bool isActive;
  final bool isVisible;
  final void Function(int startTimeMs)? onLineClick;

  const AmllLyricPlayer({
    super.key,
    required this.lines,
    required this.currentTimeMs,
    this.isPlaying = false,
    this.fontFamily = '',
    this.fontSizeRate = 1.0,
    this.fontWeight = 600,
    this.showTranslation = true,
    this.showRoman = true,
    this.enableBlur = true,
    this.enableScale = true,
    this.enableJumpLyric = false,
    this.centerAlign = false,
    this.isActive = true,
    this.isVisible = true,
    this.onLineClick,
  });

  @override
  State<AmllLyricPlayer> createState() => AmllLyricPlayerState();
}

class AmllLyricPlayerState extends State<AmllLyricPlayer>
    with SingleTickerProviderStateMixin {
  InAppWebViewController? _controller;
  bool _ready = false;
  int _linesSig = 0;
  int _anchorPositionMs = 0;
  int _anchorWallMs = 0;
  late final Ticker _ticker;
  int _tickerSkip = 0;
  bool _timeUpdateInFlight = false;
  bool _disposed = false;
  static String? _cachedHtml;
  bool _fontsInjected = false;
  Timer? _loadStopTimer;

  /// 在后台 isolate 中执行 base64 编码，避免阻塞 UI 线程
  /// （字体 12MB、JS bundle 363KB，直接编码会产生几十到几百毫秒的卡顿）。
  static String _encodeB64(Uint8List bytes) => base64Encode(bytes);

  /// 字体 base64 静态缓存：整个会话只编码一次。
  /// 之前每个 WebView 实例都会重复对 12MB 字体做 base64 编码并构造
  /// 巨型 JS 字符串，是歌词页初始化卡顿的主因。
  static final Map<String, String> _fontB64Cache = {};

  static Future<String> _fontBase64(String asset) async {
    final cached = _fontB64Cache[asset];
    if (cached != null) return cached;
    final bytes = (await rootBundle.load(asset)).buffer.asUint8List();
    final b64 = await compute(_encodeB64, bytes);
    _fontB64Cache[asset] = b64;
    return b64;
  }

  static String _buildHtml(String css, String jsB64) {
    return '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:100%;height:100%;overflow:hidden;background:transparent}
#player{width:100%;height:100%;visibility:hidden;--amll-lp-color:rgba(255,255,255,0.9);--amll-lp-font-size:calc(min(clamp(30px,2.5vw,50px),5vh));--amll-lp-hover-bg-color:rgba(255,255,255,0.08);--amll-lp-text-align:left;font-synthesis:weight style;text-align:var(--amll-lp-text-align)}
#amll-ff{font-synthesis:weight style}
$css
</style>
</head>
<body style="background:transparent">
<div id="player"></div>
<script>
try{eval(atob("$jsB64"))}catch(e){}
(function(){
  if(typeof AmllBridge!=='undefined'&&AmllBridge.init){
    try{AmllBridge.init("player")}catch(e){}
  }
})();
</script>
</body>
</html>''';
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _loadHtml();
  }

  /// 应用启动时预热 AMLL HTML（加载 bundle + 后台 isolate 编码）。
  /// 冷启动后首次打开歌词页时 WebView 能立即创建，不必等 HTML 构建，
  /// 减少「进入全屏播放页/歌词页时的卡顿」。
  static Future<void> prewarm() async {
    if (_cachedHtml != null) return;
    try {
      final js = await rootBundle.loadString('assets/amll/amll-bundle.js');
      final css = await rootBundle.loadString('assets/amll/amll-core.css');
      // bundle 的 base64 编码移到后台 isolate，避免首次构建 WebView 时
      // 在 UI 线程编码 363KB 造成掉帧。
      final jsB64 = await compute(_encodeB64, utf8.encode(js));
      _cachedHtml = _buildHtml(css, jsB64);
    } catch (e) {
      debugPrint('[AMLL] prewarm error: $e');
    }
  }

  Future<void> _loadHtml() async {
    await prewarm();
    if (mounted && !_disposed) setState(() {});
  }

  void _onWebViewCreated(InAppWebViewController c) {
    _controller = c;
    c.addJavaScriptHandler(
      handlerName: 'AmllChannel',
      callback: (args) {
        if (_disposed || !widget.isActive || args.isEmpty) return;
        try {
          final d = jsonDecode(args[0] as String) as Map<String, dynamic>;
          if (d['type'] == 'line-click') {
            widget.onLineClick?.call(d['startTime'] as int? ?? 0);
          }
        } catch (_) {}
      },
    );
  }

  void _onLoadStop(InAppWebViewController c, WebUri? url) {
    _loadStopTimer?.cancel();
    _loadStopTimer = Timer(const Duration(milliseconds: 16), () {
      if (!_disposed && widget.isActive) unawaited(_sendAll());
    });
  }

  void _syncAnchor(int positionMs, bool isPlaying) {
    if (_disposed || !widget.isActive) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final drift = (positionMs - _anchorPositionMs).abs();
    if (isPlaying && _ticker.isActive && drift <= 300) {
      final correction = ((positionMs - _anchorPositionMs) * 0.50).round();
      _anchorPositionMs = _anchorPositionMs + correction;
      _anchorWallMs = now;
    } else {
      _anchorPositionMs = positionMs;
      _anchorWallMs = now;
    }
    if (isPlaying && !_ticker.isActive) {
      _ticker.start();
    } else if (!isPlaying && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (_disposed || !widget.isActive || !_ready || _controller == null) {
      return;
    }
    _tickerSkip++;
    if (_tickerSkip % 3 != 0) return;
    if (_timeUpdateInFlight) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final smoothTimeMs = _anchorPositionMs + now - _anchorWallMs;
    _timeUpdateInFlight = true;
    final controller = _controller!;
    unawaited(
      controller
          .evaluateJavascript(
            source: 'AmllBridge.setCurrentTime($smoothTimeMs)',
          )
          .catchError((_) {})
          .whenComplete(() => _timeUpdateInFlight = false),
    );
  }

  Future<void> _sendAll() async {
    if (!_canUseWebView || _cachedHtml == null) return;
    // 先应用字体/对齐等样式，再构建歌词行：
    // 若先建行再改 CSS，所有歌词行的字号/对齐会触发二次 reflow/重布局，
    // 表现为歌词加载后（第一句/定位时）再卡一下。
    await _sendConfig();
    if (!_canUseWebView) return;
    // 字体必须在创建歌词行前完成，否则字体尺寸变化会触发 AMLL 的
    // ResizeObserver，并在歌词已经可见后再次强制重排当前句。
    if (!_fontsInjected) {
      _fontsInjected = true;
      await _injectFonts();
    }
    if (!_canUseWebView) return;
    _linesSig = _makeSignature(widget.lines);
    await _sendLyricLines();
    if (!_canUseWebView) return;
    await _sendPlaying(widget.isPlaying);
    // 先在隐藏状态下启动 AMLL 原生 spring，并在下一布局帧后再显示，
    // 避免同步 calcLayout 与 Flutter/WebView 合成器在同一可见帧争抢资源。
    await _revealAfterCurrentTime();
    // 给 AMLL 一点时间完成当前句的布局/渲染，再启动平滑跟随的 ticker，
    // 避免初始化渲染与高频更新互相争抢。
    if (!_canUseWebView) return;
    _syncAnchor(widget.currentTimeMs, widget.isPlaying);
    if (mounted && !_disposed && widget.isActive) {
      setState(() => _ready = true);
    }
  }

  bool get _canUseWebView =>
      !_disposed && widget.isActive && _controller != null;

  Future<void> _setVisible(bool visible) async {
    if (!_canUseWebView) return;
    try {
      await _controller!.evaluateJavascript(
        source:
            "(function(){var p=document.getElementById('player');if(p){p.style.visibility='${visible ? 'visible' : 'hidden'}';p.style.pointerEvents='${visible ? 'auto' : 'none'}';}})()",
      );
    } catch (_) {}
  }

  /// 确定性地冻结 WebView 的 JS 歌词动画并停止 Flutter ticker。
  ///
  /// AMLL 用 PIXI(WebGL) + requestAnimationFrame 驱动渲染，
  /// WebView 软件绘制截图（takeScreenshot）对 WebGL 画布不可靠，
  /// 会间歇性得到空白帧。因此退出动画改用「等待 JS 动画真正停止」：
  /// rAF 循环被取消后，WebGL 画布保持最后一帧，滑动期间平台视图
  /// 是静态帧，不会与 Flutter 合成器不同步而闪烁。
  Future<void> freeze() async {
    _ticker.stop();
    _tickerSkip = 0;
    final controller = _controller;
    if (controller == null || _disposed) return;
    try {
      await controller.evaluateJavascript(
        source: 'AmllBridge.setPlaying(false);AmllBridge.stopAnimation()',
      );
    } catch (_) {}
    // 留一帧让 WebView 刷新完最后的绘制（页面此时仍是静止的），
    // 保证滑动开始时平台视图已处于稳定静态帧。
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }

  void _setActive(bool active) {
    if (_disposed) return;
    if (!active) {
      _ticker.stop();
      _tickerSkip = 0;
    }
    final controller = _controller;
    if (controller == null) return;
    if (!active) {
      unawaited(
        controller
            .evaluateJavascript(
              source: 'AmllBridge.setPlaying(false);AmllBridge.stopAnimation()',
            )
            .catchError((_) {}),
      );
      return;
    }
    unawaited(_resumeActive(controller));
  }

  Future<void> _resumeActive(InAppWebViewController controller) async {
    if (!_canUseWebView) return;
    try {
      await controller.evaluateJavascript(
        source:
            "AmllBridge.startAnimation();AmllBridge.setPlaying(${widget.isPlaying ? 'true' : 'false'})",
      );
      await _sendAll();
    } catch (_) {}
  }

  /// 通过 JS FontFace API 注入自定义字体到 WebView。
  ///
  /// 关键优化：
  /// - 用户选择「系统默认」时跳过整个注入（12MB 字体完全不用加载）；
  /// - base64 编码移到后台 isolate 并静态缓存（整个会话只编码一次），
  ///   避免每个 WebView 实例在 UI 线程编码 12MB 字体导致初始化卡顿。
  /// - 注册时使用 weight:'100 900' 范围描述符，
  ///   让单一 Regular/Bold 字重文件匹配所有 CSS 字重请求，
  ///   然后靠 font-synthesis:weight 合成不同粗细。
  Future<void> _injectFonts() async {
    if (!_canUseWebView) return;
    final fam = widget.fontFamily;
    final needLyricfont = fam == 'lyricfont';
    final needPingFang = fam == 'PingFangSC-Semibold';
    if (!needLyricfont && !needPingFang) return; // 系统默认字体，无需注入

    if (needLyricfont) {
      try {
        final ttfB64 = await _fontBase64('assets/fonts/lyricfont.ttf');
        if (!_canUseWebView) return;
        await _controller!.evaluateJavascript(
          source:
              """
(async function(){
  try{
    var f=new FontFace('lyricfont','url(data:font/ttf;base64,$ttfB64)',{weight:'100 900',style:'normal'});
    f.display='swap';
    await f.load();
    document.fonts.add(f);
    var loaded=await document.fonts.load('700 16px lyricfont');
    console.log('[AMLL font-inject] lyricfont registered, loaded=',loaded.length>0);
    return true;
  }catch(e){
    console.log('[AMLL font-inject] lyricfont error:',e);
    return false;
  }
})();
""",
        );
      } catch (e) {
        debugPrint('[AMLL] lyricfont inject error: $e');
      }
    }

    if (needPingFang) {
      try {
        final woff2B64 = await _fontBase64(
          'assets/fonts/PingFangSC-Semibold.woff2',
        );
        if (!_canUseWebView) return;
        await _controller!.evaluateJavascript(
          source:
              """
(async function(){
  try{
    var f=new FontFace('PingFangSC-Semibold','url(data:font/woff2;base64,$woff2B64) format("woff2")',{weight:'100 900',style:'normal'});
    f.display='swap';
    await f.load();
    document.fonts.add(f);
    var loaded=await document.fonts.load('700 16px PingFangSC-Semibold');
    console.log('[AMLL font-inject] PingFangSC-Semibold registered, loaded=',loaded.length>0);
    return true;
  }catch(e){
    console.log('[AMLL font-inject] PingFangSC error:',e);
    return false;
  }
})();
""",
        );
      } catch (e) {
        debugPrint('[AMLL] PingFangSC inject error: $e');
      }
    }
  }

  /// 歌词 JSON 静态缓存：同一首歌 + 相同的翻译/罗马音选项时，构建结果
  /// 完全一致。避免每次重新打开歌词页都重复做逐字排序/截断 + jsonEncode
  /// （长歌词在 UI 线程会阻塞几十毫秒，叠加跳转定位造成卡顿）。
  static String? _cachedLyricJson;
  static int _cachedLyricSig = 0;

  Future<void> _sendLyricLines() async {
    if (!_canUseWebView) return;
    final sig = Object.hash(
      _linesSig,
      widget.showTranslation,
      widget.showRoman,
    );
    // 先以当前句的上一句作为初始布局，随后由 _revealAfterCurrentTime
    // 调用普通 setCurrentTime，让 AMLL 使用原生 spring 过渡到当前句。
    final initTime = _initialLayoutTime();
    if (_cachedLyricJson != null && sig == _cachedLyricSig) {
      await _controller!.evaluateJavascript(
        source:
            "AmllBridge.setLyricLines('${_escapeJsStr(_cachedLyricJson!)}', $initTime)",
      );
      return;
    }
    final lines = widget.lines;
    final adjusted = List<Map<String, dynamic>>.generate(lines.length, (i) {
      final l = lines[i];
      final lineEnd = (i < lines.length - 1)
          ? lines[i + 1].startTimeMs
          : l.endTimeMs;
      var words = l.words
          .map(
            (w) =>
                (word: w.word, startTime: w.startTimeMs, endTime: w.endTimeMs),
          )
          .toList();
      words.sort((a, b) => a.startTime.compareTo(b.startTime));
      for (int j = 0; j < words.length; j++) {
        if (words[j].endTime > lineEnd) {
          words[j] = (
            word: words[j].word,
            startTime: words[j].startTime,
            endTime: lineEnd,
          );
        }
        if (j < words.length - 1) {
          final nextStart = words[j + 1].startTime;
          if (words[j].endTime > nextStart) {
            words[j] = (
              word: words[j].word,
              startTime: words[j].startTime,
              endTime: nextStart,
            );
          } else if (words[j].endTime < nextStart) {
            words[j] = (
              word: words[j].word,
              startTime: words[j].startTime,
              endTime: nextStart,
            );
          }
        }
      }
      return {
        'startTime': l.startTimeMs,
        'endTime': lineEnd,
        'words': words
            .map(
              (w) => {
                'word': w.word,
                'startTime': w.startTime,
                'endTime': w.endTime,
              },
            )
            .toList(),
        'translatedLyric': widget.showTranslation ? l.translatedLyric : null,
        'romanLyric': widget.showRoman ? l.romanLyric : null,
        'isBG': l.isBG,
        'isDuet': l.isDuet,
        'adLibText': widget.showTranslation ? l.adLibText : null,
      };
    });
    final json = jsonEncode(adjusted);
    _cachedLyricJson = json;
    _cachedLyricSig = sig;
    await _controller!.evaluateJavascript(
      source: "AmllBridge.setLyricLines('${_escapeJsStr(json)}', $initTime)",
    );
  }

  int _initialLayoutTime() {
    final currentIndex = widget.lines.lastIndexWhere(
      (line) => line.startTimeMs <= widget.currentTimeMs,
    );
    if (currentIndex <= 0) return widget.currentTimeMs;
    return widget.lines[currentIndex - 1].startTimeMs;
  }

  Future<void> _revealAfterCurrentTime() async {
    if (!_canUseWebView) return;
    try {
      await _controller!.evaluateJavascript(
        source:
            """
(function(){
  var p=document.getElementById('player');
  if(!p)return;
  p.style.visibility='hidden';
  p.style.pointerEvents='none';
  requestAnimationFrame(function(){
    AmllBridge.setCurrentTime(${widget.currentTimeMs});
    requestAnimationFrame(function(){
      p.style.visibility='${widget.isVisible ? 'visible' : 'hidden'}';
      p.style.pointerEvents='${widget.isVisible ? 'auto' : 'none'}';
    });
  });
})();
""",
      );
    } catch (_) {}
  }

  Future<void> _sendPlaying(bool p) async {
    if (!_canUseWebView) return;
    await _controller!.evaluateJavascript(
      source: 'AmllBridge.setPlaying(${p ? "true" : "false"})',
    );
  }

  Future<void> _sendConfig() async {
    if (!_canUseWebView) return;
    final cfg = jsonEncode({
      'enableBlur': widget.enableBlur,
      'enableScale': widget.enableScale,
      'alignPosition': 0.5,
      'wordFadeWidth': 0.5,
      'enableSpring': widget.enableJumpLyric,
      'fontFamily': widget.fontFamily,
      'fontSizeRate': widget.fontSizeRate,
      'fontWeight': widget.fontWeight,
      'centerAlign': widget.centerAlign,
    });
    await _controller!.evaluateJavascript(
      source: "AmllBridge.setConfig('${_escapeJsStr(cfg)}')",
    );
    // fontFamily / fontWeight 全局强制覆盖：AMLL 内部元素不继承父级字体样式
    // 居中对齐需要覆盖 flex 容器 align-items 以及内部 text-align，仅改 text-align 不够
    final escapedFontFamily = widget.fontFamily
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'");
    final isSystemFont =
        escapedFontFamily.isEmpty || escapedFontFamily == 'system';
    final fontFamCss = isSystemFont
        ? 'sans-serif'
        : "'$escapedFontFamily',sans-serif";
    final alignCss = widget.centerAlign
        ? '#player .FmKaba_lyricLineWrapper{align-items:center !important}#player .FmKaba_lyricLine{text-align:center !important;justify-content:center !important;transform-origin:center center !important;contain:none !important}#player .FmKaba_lyricMainLine{display:flex !important;justify-content:center !important;flex-wrap:wrap !important;text-align:center !important}#player .FmKaba_lyricMainLine > *,#player .FmKaba_lyricMainLine span{display:inline-block !important;text-align:center !important}#player .FmKaba_lyricDuetLine{text-align:center !important}#player .FmKaba_interludeDots{width:100% !important;justify-content:center !important}#player .FmKaba_hasDuetLine .FmKaba_lyricLine:not(.FmKaba_lyricDuetLine){padding-right:1em !important}#player .FmKaba_hasDuetLine .FmKaba_lyricDuetLine{padding-left:1em !important}'
        : '#player .FmKaba_lyricLineWrapper{align-items:flex-start !important}#player .FmKaba_lyricLine{text-align:start !important;justify-content:flex-start !important;transform-origin:0 0 !important;contain:content !important}#player .FmKaba_lyricMainLine{display:block !important;justify-content:flex-start !important;text-align:start !important}#player .FmKaba_lyricMainLine > *,#player .FmKaba_lyricMainLine span{display:inline-block !important;text-align:start !important}#player .FmKaba_lyricDuetLine{text-align:right !important}#player .FmKaba_interludeDots{width:fit-content !important;justify-content:flex-start !important}#player .FmKaba_hasDuetLine .FmKaba_lyricLine:not(.FmKaba_lyricDuetLine){padding-right:15% !important}#player .FmKaba_hasDuetLine .FmKaba_lyricDuetLine{padding-left:15% !important}';
    final cssContent =
        '#player,#player *{font-family:$fontFamCss !important;font-weight:${widget.fontWeight} !important;font-synthesis:weight style !important}$alignCss';
    final escapedCssForJs = _escapeJsStr(cssContent);
    if (!_canUseWebView) return;
    await _controller!.evaluateJavascript(
      source:
          """
(function(){
  var s=document.getElementById('amll-ff')||document.createElement('style');
  s.id='amll-ff';
  s.textContent='$escapedCssForJs';
  var player=document.getElementById('player');
  if(player)player.style.setProperty('--amll-lp-text-align','${widget.centerAlign ? 'center' : 'left'}');
  if(!s.parentNode)document.head.appendChild(s);
})();
""",
    );
  }

  String _escapeJsStr(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll("'", "\\'")
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r');

  int _makeSignature(List<LyricLine> lines) => Object.hashAll(
    lines.map(
      (l) =>
          Object.hash(l.startTimeMs, l.endTimeMs, l.plainText, l.words.length),
    ),
  );

  @override
  void didUpdateWidget(covariant AmllLyricPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _setActive(widget.isActive);
    }
    if (!widget.isActive) return;
    if (oldWidget.currentTimeMs != widget.currentTimeMs ||
        oldWidget.isPlaying != widget.isPlaying) {
      _syncAnchor(widget.currentTimeMs, widget.isPlaying);
    }
    if (!_ready || _controller == null) return;
    if (oldWidget.isVisible != widget.isVisible) {
      _setVisible(widget.isVisible);
    }
    if (oldWidget.isPlaying != widget.isPlaying) {
      _sendPlaying(widget.isPlaying);
    }
    final displayChanged =
        oldWidget.showTranslation != widget.showTranslation ||
        oldWidget.showRoman != widget.showRoman;
    final configChanged =
        oldWidget.enableBlur != widget.enableBlur ||
        oldWidget.enableScale != widget.enableScale ||
        oldWidget.enableJumpLyric != widget.enableJumpLyric ||
        oldWidget.fontFamily != widget.fontFamily ||
        oldWidget.fontSizeRate != widget.fontSizeRate ||
        oldWidget.fontWeight != widget.fontWeight ||
        oldWidget.centerAlign != widget.centerAlign;
    if (displayChanged) {
      _sendLyricLines();
    }
    if (configChanged) {
      _sendConfig();
    }
    final s = _makeSignature(widget.lines);
    if (s != _linesSig) {
      _linesSig = s;
      _sendLyricLines();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loadStopTimer?.cancel();
    _ticker.dispose();
    // 不调用 evaluateJavascript，WebView 销毁时 JS 引擎自动清理
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cachedHtml == null) {
      return const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return InAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
        supportZoom: false,
      ),
      initialData: InAppWebViewInitialData(
        data: _cachedHtml!,
        mimeType: 'text/html',
        encoding: 'utf8',
        baseUrl: WebUri('https://amll.local/'),
      ),
      onWebViewCreated: _onWebViewCreated,
      onLoadStop: _onLoadStop,
    );
  }
}
