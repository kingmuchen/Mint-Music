import 'song.dart';
import 'play_mode.dart';

class PlaybackState {
  final Song? currentSong;
  final bool isPlaying;
  final Duration position;
  final Duration buffered;
  final Duration actualDuration;
  final PlayMode playMode;
  final List<Song> queue;
  final int currentIndex;
  final bool isLoading;
  final String currentQuality;
  final List<String> availableQualities;

  const PlaybackState({
    this.currentSong,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.buffered = Duration.zero,
    this.actualDuration = Duration.zero,
    this.playMode = PlayMode.listLoop,
    this.queue = const [],
    this.currentIndex = -1,
    this.isLoading = false,
    this.currentQuality = '320k',
    this.availableQualities = const [
      '128k',
      '320k',
      'flac',
      'flac24bit',
      'hires',
      'atmos',
      'master',
    ],
  });

  Duration get duration {
    if (actualDuration != Duration.zero) {
      return actualDuration;
    }
    if (currentSong?.duration != null && currentSong!.duration > 0) {
      return Duration(seconds: currentSong!.duration);
    }
    return Duration.zero;
  }

  double get progress {
    if (duration == Duration.zero) return 0;
    return position.inMilliseconds / duration.inMilliseconds;
  }

  bool get hasPrevious => queue.isNotEmpty;

  bool get hasNext => queue.isNotEmpty;

  PlaybackState copyWith({
    Song? currentSong,
    bool? isPlaying,
    Duration? position,
    Duration? buffered,
    Duration? actualDuration,
    PlayMode? playMode,
    List<Song>? queue,
    int? currentIndex,
    bool? isLoading,
    String? currentQuality,
    List<String>? availableQualities,
    bool forceCurrentSong = false,
  }) {
    final newCurrentSong = forceCurrentSong
        ? currentSong
        : (currentSong ?? this.currentSong);
    final newIsPlaying = isPlaying ?? this.isPlaying;
    final newPosition = position ?? this.position;
    final newBuffered = buffered ?? this.buffered;
    final newActualDuration = actualDuration ?? this.actualDuration;
    final newPlayMode = playMode ?? this.playMode;
    final newQueue = queue ?? this.queue;
    final newCurrentIndex = currentIndex ?? this.currentIndex;
    final newIsLoading = isLoading ?? this.isLoading;
    final newCurrentQuality = currentQuality ?? this.currentQuality;
    final newAvailableQualities = availableQualities ?? this.availableQualities;

    if (!forceCurrentSong &&
        newCurrentSong == this.currentSong &&
        newIsPlaying == this.isPlaying &&
        newPosition == this.position &&
        newBuffered == this.buffered &&
        newActualDuration == this.actualDuration &&
        newPlayMode == this.playMode &&
        identical(newQueue, this.queue) &&
        newCurrentIndex == this.currentIndex &&
        newIsLoading == this.isLoading &&
        newCurrentQuality == this.currentQuality &&
        identical(newAvailableQualities, this.availableQualities)) {
      return this;
    }

    return PlaybackState(
      currentSong: newCurrentSong,
      isPlaying: newIsPlaying,
      position: newPosition,
      buffered: newBuffered,
      actualDuration: newActualDuration,
      playMode: newPlayMode,
      queue: newQueue,
      currentIndex: newCurrentIndex,
      isLoading: newIsLoading,
      currentQuality: newCurrentQuality,
      availableQualities: newAvailableQualities,
    );
  }
}
