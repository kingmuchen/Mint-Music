import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/physics.dart';
import '../../domain/models/lyric_line.dart';

/// Apple Music 风格原生歌词滚动组件
///
/// 与 [lyric_scroll_view.dart] 的 [LyricScrollView] 功能相同，
/// 但增加了 AMLL 标志性的弹簧物理动画和渐变遮罩逐字渲染。
///
/// 完全在 Flutter 原生侧实现，不依赖 WebView。
class AmllLyricView extends StatefulWidget {
  final List<LyricLine> lines;
  final int currentTimeMs;
  final bool isPlaying;
  final bool hasYrc;
  final Color activeColor;
  final Color inactiveColor;
  final double mainFontSize;
  final double transFontSize;
  final double romanFontSize;
  final bool enableBlur;
  final bool enableScale;
  final bool enableJumpLyric;
  final bool showTranslation;
  final bool showRoman;
  final ValueChanged<int>? onSeek;

  const AmllLyricView({
    super.key,
    required this.lines,
    required this.currentTimeMs,
    this.isPlaying = false,
    this.hasYrc = false,
    this.activeColor = Colors.white,
    this.inactiveColor = const Color(0x40FFFFFF),
    this.mainFontSize = 30,
    this.transFontSize = 16,
    this.romanFontSize = 14,
    this.enableBlur = true,
    this.enableScale = true,
    this.enableJumpLyric = false,
    this.showTranslation = true,
    this.showRoman = true,
    this.onSeek,
  });

  @override
  State<AmllLyricView> createState() => _AmllLyricViewState();
}

class _AmllLyricViewState extends State<AmllLyricView>
    with SingleTickerProviderStateMixin {
  static const _userScrollTimeout = Duration(milliseconds: 3000);
  static const _fadeTopStop = 0.15;
  static const _fadeBottomStop = 0.86;

  final _scrollController = ScrollController();
  final _lineKeys = <GlobalKey>[];
  final _clock = _LyricClock();
  late final Ticker _ticker;
  Timer? _userScrollTimer;

  bool _userScrolling = false;
  bool _autoScrolling = false;
  int _scrollTargetIndex = -1;
  int _centerLineIndex = -1;
  int _linesSignature = 0;
  int _activeSignature = 0;
  int _anchorPositionMs = 0;
  int _anchorWallMs = 0;

  // 弹簧动画
  late final AnimationController _springCtrl;
  double _springStart = 0;
  double _springEnd = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_handleTick);
    _springCtrl = AnimationController(vsync: this);
    _springCtrl.addListener(_onSpringUpdate);
    _ensureLineKeys();
    _linesSignature = _makeLinesSignature(widget.lines);
    _syncClock(widget.currentTimeMs, widget.isPlaying);
    _activeSignature = _makeActiveSignature(_activeIndicesFor(_clock.timeMs));
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToActiveLine(force: true);
    });
  }

  @override
  void didUpdateWidget(covariant AmllLyricView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _makeLinesSignature(widget.lines);
    if (signature != _linesSignature) {
      _linesSignature = signature;
      _ensureLineKeys();
      _scrollTargetIndex = -1;
      _centerLineIndex = -1;
      _syncClock(widget.currentTimeMs, widget.isPlaying);
      _activeSignature = _makeActiveSignature(_activeIndicesFor(_clock.timeMs));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveLine(force: true);
      });
      setState(() {});
      return;
    }
    if (oldWidget.currentTimeMs != widget.currentTimeMs ||
        oldWidget.isPlaying != widget.isPlaying) {
      _syncClock(widget.currentTimeMs, widget.isPlaying);
      _updateActiveLinesAndScroll();
    }
  }

  @override
  void dispose() {
    _userScrollTimer?.cancel();
    _ticker.dispose();
    _springCtrl.dispose();
    _clock.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _ensureLineKeys() {
    while (_lineKeys.length < widget.lines.length) {
      _lineKeys.add(GlobalKey());
    }
    if (_lineKeys.length > widget.lines.length) {
      _lineKeys.removeRange(widget.lines.length, _lineKeys.length);
    }
  }

  int _makeLinesSignature(List<LyricLine> lines) {
    return Object.hashAll(
      lines.map(
        (l) => Object.hash(
          l.startTimeMs,
          l.endTimeMs,
          l.words.length,
          l.plainText,
          l.translatedLyric,
          l.romanLyric,
          l.adLibText,
        ),
      ),
    );
  }

  int _makeActiveSignature(List<int> indices) => Object.hashAll(indices);

  void _syncClock(int positionMs, bool isPlaying) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final drift = (positionMs - _clock.timeMs).abs();
    if (isPlaying && _ticker.isActive && drift <= 200) {
      final correction = ((positionMs - _clock.timeMs) * 0.50).round();
      _anchorPositionMs = _clock.timeMs + correction;
      _anchorWallMs = now;
    } else {
      _anchorPositionMs = positionMs;
      _anchorWallMs = now;
      _clock.setTime(positionMs);
      if (drift > 500) {
        _activeSignature = 0;
        _userScrolling = false;
        _userScrollTimer?.cancel();
        _scrollTargetIndex = -1;
      }
    }
    if (isPlaying && !_ticker.isActive) {
      _ticker.start();
    } else if (!isPlaying && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _handleTick(Duration elapsed) {
    if (!widget.isPlaying) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final smoothTimeMs = _anchorPositionMs + now - _anchorWallMs;
    _clock.setTime(smoothTimeMs);
    _updateActiveLinesAndScroll(fromTicker: true);
  }

  void _updateActiveLinesAndScroll({bool fromTicker = false}) {
    final activeIndices = _activeIndicesFor(_clock.timeMs);
    final signature = _makeActiveSignature(activeIndices);
    if (signature == _activeSignature) return;
    _activeSignature = signature;
    if (!mounted) return;
    setState(() {});
    if (!_userScrolling) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveLine(force: true);
      });
    }
  }

  List<int> _activeIndicesFor(int timeMs) {
    if (widget.lines.isEmpty) return const [];
    if (widget.hasYrc) {
      final activeIndex = widget.lines.lastIndexWhere(
        (line) => line.startTimeMs <= timeMs,
      );
      if (activeIndex < 0) return [0];
      return [activeIndex];
    }
    final activeIndex = widget.lines.lastIndexWhere(
      (line) => line.startTimeMs <= timeMs,
    );
    if (activeIndex < 0) return [0];
    return [activeIndex];
  }

  int _activeScrollTargetIndex() {
    final indices = _activeIndicesFor(_clock.timeMs);
    return indices.isEmpty ? -1 : indices.last;
  }

  void _handleScroll() {
    if (_autoScrolling) return;
    if (!_userScrolling) {
      setState(() => _userScrolling = true);
    }
    _userScrollTimer?.cancel();
    _userScrollTimer = Timer(_userScrollTimeout, () {
      if (!mounted) return;
      setState(() {
        _userScrolling = false;
        _centerLineIndex = -1;
      });
      _scrollToActiveLine(force: true);
    });
    final index = _findCenterLineIndex();
    if (index != _centerLineIndex && mounted) {
      setState(() => _centerLineIndex = index);
    }
  }

  int _findCenterLineIndex() {
    final container = context.findRenderObject() as RenderBox?;
    if (container == null || widget.lines.isEmpty) return -1;
    final centerY = container.size.height / 2;
    var closestIndex = -1;
    var closestDistance = double.infinity;
    for (var i = 0; i < _lineKeys.length; i++) {
      final lineContext = _lineKeys[i].currentContext;
      if (lineContext == null) continue;
      final box = lineContext.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final offset = box.localToGlobal(Offset.zero, ancestor: container);
      final lineCenterY = offset.dy + box.size.height / 2;
      final distance = (lineCenterY - centerY).abs();
      if (distance < closestDistance) {
        closestDistance = distance;
        closestIndex = i;
      }
    }
    return closestIndex;
  }

  void _scrollToActiveLine({bool force = false}) {
    if (!mounted ||
        _userScrolling ||
        _autoScrolling ||
        !_scrollController.hasClients)
      return;
    final targetIndex = _activeScrollTargetIndex();
    if (targetIndex < 0 || targetIndex >= _lineKeys.length) return;
    if (!force && targetIndex == _scrollTargetIndex) return;

    final lineContext = _lineKeys[targetIndex].currentContext;
    if (lineContext == null) {
      _estimateScrollToIndex(targetIndex);
      return;
    }

    final lineBox = lineContext.findRenderObject() as RenderBox?;
    final scrollBox =
        _scrollController.position.context.storageContext.findRenderObject()
            as RenderBox?;
    if (lineBox == null ||
        scrollBox == null ||
        !lineBox.hasSize ||
        !scrollBox.hasSize)
      return;

    final lineOffset = lineBox.localToGlobal(Offset.zero, ancestor: scrollBox);
    final targetOffset =
        _scrollController.offset +
        lineOffset.dy -
        (scrollBox.size.height - lineBox.size.height) * 0.5;

    _animateToOffsetSpring(targetOffset);
    _scrollTargetIndex = targetIndex;
  }

  void _estimateScrollToIndex(int index) {
    final estimatedLineHeight = max(48.0, widget.mainFontSize * 2.4);
    final viewportHeight = _scrollController.position.viewportDimension;
    final verticalPadding = viewportHeight * 0.45;
    final targetOffset = verticalPadding + index * estimatedLineHeight;
    _animateToOffsetSpring(targetOffset);
    _scrollTargetIndex = index;
  }

  /// Apple Music 风格弹簧滚动
  void _animateToOffsetSpring(double targetOffset) {
    final position = _scrollController.position;
    final clamped = targetOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final start = position.pixels;
    final distance = clamped - start;

    if (!widget.enableJumpLyric) {
      _autoScrolling = false;
      position.jumpTo(clamped);
      return;
    }

    if (distance.abs() < 1.0) {
      position.jumpTo(clamped);
      return;
    }

    _springStart = start;
    _springEnd = clamped;
    _scrollTargetIndex = -1;

    // 使用弹簧物理模拟
    _springCtrl.reset();
    _springCtrl.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 150, damping: 20),
        0,
        1,
        0, // 归一化到 0→1
      ),
    );
  }

  void _onSpringUpdate() {
    if (!_springCtrl.isAnimating) {
      _autoScrolling = false;
      _scrollTargetIndex = -1;
      return;
    }
    _autoScrolling = true;
    final t = _springCtrl.value;
    final pos = _springStart + (_springEnd - _springStart) * t;
    _scrollController.position.jumpTo(pos);
    if (_springCtrl.isCompleted) {
      _autoScrolling = false;
    }
  }

  String _formatTime(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lines.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(
            fontSize: widget.mainFontSize * 0.6,
            color: widget.inactiveColor,
          ),
        ),
      );
    }

    final activeIndices = _activeIndicesFor(_clock.timeMs).toSet();
    final activeIndex = activeIndices.isEmpty ? -1 : activeIndices.last;
    final centerLine =
        _centerLineIndex >= 0 && _centerLineIndex < widget.lines.length
        ? widget.lines[_centerLineIndex]
        : null;

    return Stack(
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: [0, _fadeTopStop, _fadeBottomStop, 1],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewportHeight = constraints.maxHeight;
              final verticalPadding = viewportHeight * 0.45;
              return ListView.builder(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                cacheExtent: viewportHeight,
                padding: EdgeInsets.only(
                  top: verticalPadding,
                  bottom: viewportHeight - verticalPadding,
                ),
                itemCount: widget.lines.length,
                itemBuilder: (context, index) {
                  final isActive = activeIndices.contains(index);
                  return _AmllLineWidget(
                    key: _lineKeys[index],
                    line: widget.lines[index],
                    clock: _clock,
                    staticTimeMs: _clock.timeMs,
                    isActive: isActive,
                    activeIndex: activeIndex,
                    index: index,
                    activeColor: widget.activeColor,
                    inactiveColor: widget.inactiveColor,
                    mainFontSize: widget.mainFontSize,
                    transFontSize: widget.transFontSize,
                    romanFontSize: widget.romanFontSize,
                    enableBlur: widget.enableBlur,
                    userScrolling: _userScrolling,
                    hasYrc: widget.hasYrc,
                    showTranslation: widget.showTranslation,
                    showRoman: widget.showRoman,
                  );
                },
              );
            },
          ),
        ),
        if (_userScrolling && centerLine != null) ...[
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Text(
                        _formatTime(centerLine.startTimeMs),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.35),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 0,
            bottom: 0,
            child: Center(
              child: GestureDetector(
                onTap: () {
                  final seekTimeMs = centerLine.startTimeMs;
                  widget.onSeek?.call(seekTimeMs);
                  _userScrollTimer?.cancel();
                  _clock.setTime(seekTimeMs);
                  _anchorPositionMs = seekTimeMs;
                  _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
                  _activeSignature = _makeActiveSignature(
                    _activeIndicesFor(_clock.timeMs),
                  );
                  setState(() {
                    _userScrolling = false;
                    _centerLineIndex = -1;
                  });
                  _scrollToActiveLine(force: true);
                },
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// AMLL 风格歌词行（弹簧动画 + 渐变遮罩）
class _AmllLineWidget extends StatelessWidget {
  final LyricLine line;
  final _LyricClock clock;
  final int staticTimeMs;
  final bool isActive;
  final int activeIndex;
  final int index;
  final Color activeColor;
  final Color inactiveColor;
  final double mainFontSize;
  final double transFontSize;
  final double romanFontSize;
  final bool enableBlur;
  final bool userScrolling;
  final bool hasYrc;
  final bool showTranslation;
  final bool showRoman;

  const _AmllLineWidget({
    super.key,
    required this.line,
    required this.clock,
    required this.staticTimeMs,
    required this.isActive,
    required this.activeIndex,
    required this.index,
    required this.activeColor,
    required this.inactiveColor,
    required this.mainFontSize,
    required this.transFontSize,
    required this.romanFontSize,
    required this.enableBlur,
    required this.userScrolling,
    required this.hasYrc,
    required this.showTranslation,
    required this.showRoman,
  });

  @override
  Widget build(BuildContext context) {
    final distance = activeIndex < 0 ? 3 : (index - activeIndex).abs();
    final opacity = isActive ? 1.0 : 0.25;
    final scale = isActive ? 1.05 : 0.9;

    Widget mainContent = _buildMainLyric();
    if (showRoman && (line.romanLyric?.isNotEmpty ?? false)) {
      mainContent = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          mainContent,
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              line.romanLyric!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: romanFontSize,
                height: 1.3,
                fontWeight: FontWeight.w400,
                color: activeColor.withValues(alpha: isActive ? 0.5 : 0.3),
              ),
            ),
          ),
        ],
      );
    }

    final shouldBlur =
        enableBlur && !userScrolling && !isActive && distance > 0;

    Widget animatedLine = RepaintBoundary(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        opacity: opacity,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          scale: scale,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 13),
            child: mainContent,
          ),
        ),
      ),
    );

    final hasAdLib = line.adLibText != null && line.adLibText!.isNotEmpty;
    final hasTrans =
        showTranslation && (line.translatedLyric?.isNotEmpty ?? false);
    Widget? subLine;

    if (hasTrans) {
      subLine = Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 8),
        child: Text(
          hasAdLib ? line.translatedLyric! : (line.translatedLyric ?? ''),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: transFontSize,
            height: 1.35,
            fontWeight: FontWeight.w500,
            color: activeColor.withValues(alpha: 0.6),
          ),
        ),
      );
    } else if (hasAdLib) {
      subLine = Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 8),
        child: Text(
          line.adLibText!,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: transFontSize * 0.85,
            height: 1.3,
            fontWeight: FontWeight.w400,
            color: activeColor.withValues(alpha: isActive ? 0.5 : 0.25),
          ),
        ),
      );
    }

    final combined = subLine != null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [animatedLine, subLine],
          )
        : animatedLine;

    if (shouldBlur) {
      final sigma = min(1.2 + pow(distance, 0.7) * 1.5, 8).toDouble();
      return ClipRect(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: combined,
        ),
      );
    }
    return combined;
  }

  Widget _buildMainLyric() {
    if (!hasYrc || line.words.isEmpty) {
      return Text(
        line.plainText,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: mainFontSize,
          height: 1.32,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
          color: isActive ? activeColor : inactiveColor,
        ),
      );
    }

    // AMLL 风格：ShaderMask 渐变遮罩逐字填充
    final currentTimeMs = clock.timeMs ?? staticTimeMs;
    final words = _buildWordWidgets(currentTimeMs);
    if (words.isEmpty) {
      return Text(
        line.plainText,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: mainFontSize,
          height: 1.32,
          fontWeight: FontWeight.w700,
          color: isActive ? activeColor : inactiveColor,
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 2,
      runSpacing: 0,
      children: words,
    );
  }

  List<Widget> _buildWordWidgets(int currentTimeMs) {
    final words = <Widget>[];
    for (final word in line.words) {
      if (word.word.isEmpty) continue;
      final w = word.word;

      if (!isActive || word.startTimeMs >= word.endTimeMs) {
        words.add(
          Text(
            w,
            style: TextStyle(
              fontSize: mainFontSize,
              height: 1.32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.25,
              color: currentTimeMs >= word.startTimeMs
                  ? activeColor
                  : inactiveColor,
            ),
          ),
        );
        continue;
      }

      final progress =
          ((currentTimeMs - word.startTimeMs) /
                  max(1, word.endTimeMs - word.startTimeMs))
              .clamp(0.0, 1.0);

      if (progress <= 0) {
        words.add(
          Text(
            w,
            style: TextStyle(
              fontSize: mainFontSize,
              height: 1.32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.25,
              color: inactiveColor,
            ),
          ),
        );
        continue;
      }

      // 使用 ShaderMask 实现 AMLL 风格渐变遮罩
      words.add(
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [activeColor, activeColor, inactiveColor, inactiveColor],
            stops: [0, progress - 0.15, progress, 1],
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: Text(
            w,
            style: TextStyle(
              fontSize: mainFontSize,
              height: 1.32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.25,
              color: Colors.white,
            ),
          ), // 颜色由 ShaderMask 控制
        ),
      );
    }
    return words;
  }
}

class _LyricClock extends ChangeNotifier {
  int _timeMs = 0;
  int get timeMs => _timeMs;
  void setTime(int value) {
    if (value == _timeMs) return;
    _timeMs = value;
    notifyListeners();
  }
}
