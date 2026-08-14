import 'package:flutter/material.dart';
import '../../domain/models/play_mode.dart';
import '../../../settings/application/settings_providers.dart';

/// 根据音质标识和时长（秒）估算文件大小
String _estimateSize(String qualityId, int durationSec) {
  if (durationSec <= 0) return '';
  final kbps = <String, int>{
    '128k': 128,
    '192k': 192,
    '320k': 320,
    'flac': 1000,
    'flac24bit': 2000,
    'hires': 3000,
    'atmos': 500,
    'master': 3000,
  };
  final bitrate = kbps[qualityId] ?? 320;
  final sizeBytes = bitrate * 1000 ~/ 8 * durationSec;
  if (sizeBytes < 1024 * 1024) {
    return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
  }
  return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)}MB';
}

class PlayerProgressBar extends StatefulWidget {
  final double progress;
  final Duration position;
  final Duration duration;
  final ValueChanged<double> onSeek;
  final String currentQuality;
  final List<String> availableQualities;
  final ValueChanged<String>? onQualityTap;

  const PlayerProgressBar({
    super.key,
    required this.progress,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.currentQuality = '320k',
    this.availableQualities = const [],
    this.onQualityTap,
  });

  @override
  State<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends State<PlayerProgressBar> {
  bool _isDragging = false;
  double _dragProgress = 0.0;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  double get _displayProgress => _isDragging ? _dragProgress : widget.progress;

  double _getProgress(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPosition);
    return (local.dx / box.size.width).clamp(0.0, 1.0);
  }

  void _showQualityPicker() {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        overlay.size.width / 2 - 60,
        overlay.size.height - 320,
        overlay.size.width / 2 + 60,
        overlay.size.height - 180,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: const Color(0xFF282828),
      elevation: 8,
      items: widget.availableQualities.map((q) {
        final displayName = getQualityDisplayName(q);
        final sizeStr = _estimateSize(q, widget.duration.inSeconds);
        return PopupMenuItem<String>(
          value: q,
          height: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 13,
                      color: q == widget.currentQuality
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.7),
                      fontWeight: q == widget.currentQuality
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  if (sizeStr.isNotEmpty)
                    Text(
                      sizeStr,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
              if (q == widget.currentQuality)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.check, size: 14, color: Colors.white),
                ),
            ],
          ),
        );
      }).toList(),
    ).then((selected) {
      if (selected != null && selected != widget.currentQuality) {
        widget.onQualityTap?.call(selected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTapDown: (d) {
              final p = _getProgress(d.globalPosition);
              widget.onSeek(p);
            },
            onPanStart: (d) {
              setState(() {
                _isDragging = true;
                _dragProgress = _getProgress(d.globalPosition);
              });
            },
            onPanUpdate: (d) {
              setState(() {
                _dragProgress = _getProgress(d.globalPosition);
              });
            },
            onPanEnd: (_) {
              widget.onSeek(_dragProgress);
              setState(() {
                _isDragging = false;
              });
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final barWidth = constraints.maxWidth;
                  final progressWidth = barWidth * _displayProgress;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SizedBox(
                        height: 6,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 6,
                        child: Container(
                          width: progressWidth,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.3),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_isDragging)
                        Positioned(
                          left: progressWidth - 6,
                          top: -3,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Colors.white24, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                Text(
                  _formatDuration(
                    _isDragging
                        ? Duration(
                            milliseconds:
                                (widget.duration.inMilliseconds * _dragProgress)
                                    .round(),
                          )
                        : widget.position,
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                if (widget.availableQualities.isNotEmpty)
                  GestureDetector(
                    onTap: _showQualityPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        getQualityDisplayName(widget.currentQuality),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  _formatDuration(widget.duration),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PlaybackControlRow extends StatelessWidget {
  final bool isPlaying;
  final bool isLoading;
  final PlayMode playMode;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onCycleMode;
  final VoidCallback onQueue;

  const PlaybackControlRow({
    super.key,
    required this.isPlaying,
    required this.isLoading,
    required this.playMode,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onCycleMode,
    required this.onQueue,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _ControlButton(icon: _playModeIcon, size: 20, onPressed: onCycleMode),
          _ControlButton(
            icon: Icons.skip_previous,
            size: 24,
            onPressed: onPrevious,
          ),
          _PlayPauseButton(
            isPlaying: isPlaying,
            isLoading: isLoading,
            onPressed: onPlayPause,
          ),
          _ControlButton(icon: Icons.skip_next, size: 24, onPressed: onNext),
          _ControlButton(icon: Icons.queue_music, size: 22, onPressed: onQueue),
        ],
      ),
    );
  }

  IconData get _playModeIcon {
    switch (playMode) {
      case PlayMode.singleLoop:
        return Icons.repeat_one;
      case PlayMode.shuffle:
        return Icons.shuffle;
      case PlayMode.listLoop:
        return Icons.repeat;
    }
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.icon,
    required this.size,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: size),
        color: Colors.white.withValues(alpha: 0.7),
        style: IconButton.styleFrom(
          hoverColor: Colors.white.withValues(alpha: 0.1),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onPressed;

  const _PlayPauseButton({
    required this.isPlaying,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 遵循 CeruMusic/Sollin-Music：加载期间禁用按钮，避免连点
      onTap: isLoading ? null : onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: isLoading
            ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.black,
                  ),
                ),
              )
            : Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                size: 32,
                color: Colors.black,
              ),
      ),
    );
  }
}
