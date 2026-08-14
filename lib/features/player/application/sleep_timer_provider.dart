import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'playback_controller.dart';

/// 定时关闭（睡眠定时）状态。
///
/// 参考 Sollin-Music 的实现：
/// - 设定结束时间戳 endAt，每秒用定时器刷新剩余时间 remaining；
/// - 到点后回调 onFire 暂停播放，并清空定时状态。
class SleepTimerState {
  const SleepTimerState({
    this.active = false,
    this.remaining = Duration.zero,
    this.endAt,
  });

  /// 是否已设定定时关闭。
  final bool active;

  /// 距离自动暂停的剩余时间（每秒刷新）。
  final Duration remaining;

  /// 预计暂停播放的时间戳。
  final DateTime? endAt;

  SleepTimerState copyWith({
    bool? active,
    Duration? remaining,
    DateTime? endAt,
  }) {
    return SleepTimerState(
      active: active ?? this.active,
      remaining: remaining ?? this.remaining,
      endAt: endAt ?? this.endAt,
    );
  }

  static const idle = SleepTimerState();
}

class SleepTimerController extends StateNotifier<SleepTimerState> {
  SleepTimerController({required Future<void> Function() onFire})
      : _onFire = onFire,
        super(SleepTimerState.idle);

  final Future<void> Function() _onFire;

  Timer? _ticker;

  /// 启动定时关闭。duration 必须大于零，再次调用会重置并覆盖旧定时。
  void start(Duration duration) {
    if (duration <= Duration.zero) return;
    _ticker?.cancel();
    final endAt = DateTime.now().add(duration);
    state = SleepTimerState(active: true, remaining: duration, endAt: endAt);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = endAt.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        _ticker?.cancel();
        _ticker = null;
        state = SleepTimerState.idle;
        _onFire();
      } else {
        state = state.copyWith(remaining: remaining);
      }
    });
  }

  /// 取消定时关闭。
  void cancel() {
    _ticker?.cancel();
    _ticker = null;
    if (state.active) {
      state = SleepTimerState.idle;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final sleepTimerProvider =
    StateNotifierProvider<SleepTimerController, SleepTimerState>((ref) {
  return SleepTimerController(
    onFire: () async {
      // 到点暂停播放（若已暂停则为空操作）。
      await ref.read(playbackControllerProvider.notifier).pause();
      debugPrint('[SleepTimer] 定时时间到，已暂停播放');
    },
  );
});

/// 将剩余时长格式化为 "m:ss" 或 "h:mm:ss"（如 29:59 / 1:02:03）。
String formatSleepTimerRemaining(Duration duration) {
  final totalSec = duration.inSeconds;
  if (totalSec <= 0) return '0:00';
  final h = totalSec ~/ 3600;
  final m = (totalSec % 3600) ~/ 60;
  final s = totalSec % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}
