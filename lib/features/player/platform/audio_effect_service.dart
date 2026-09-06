import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The values in this object mirror the settings screen and are deliberately
/// platform neutral. Android applies the effects when a valid audio session
/// is available; other platforms simply ignore the request.
class AudioEffectsConfig {
  final bool masterEnabled;
  final bool equalizerEnabled;
  final List<double> equalizerBands;
  final bool bassBoostEnabled;
  final double bassBoostGain;
  final bool surroundEnabled;
  final String surroundMode;
  final bool balanceEnabled;
  final double balance;
  final bool visualizerEnabled;

  const AudioEffectsConfig({
    this.masterEnabled = false,
    this.equalizerEnabled = false,
    this.equalizerBands = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    this.bassBoostEnabled = false,
    this.bassBoostGain = 6,
    this.surroundEnabled = false,
    this.surroundMode = 'small',
    this.balanceEnabled = false,
    this.balance = 0,
    this.visualizerEnabled = false,
  });

  Map<String, dynamic> toMap() => {
    'masterEnabled': masterEnabled,
    'equalizerEnabled': equalizerEnabled,
    'equalizerBands': equalizerBands,
    'bassBoostEnabled': bassBoostEnabled,
    'bassBoostGain': bassBoostGain,
    'surroundEnabled': surroundEnabled,
    'surroundMode': surroundMode,
    'balanceEnabled': balanceEnabled,
    'balance': balance,
    'visualizerEnabled': visualizerEnabled,
  };
}

class AudioEffectService {
  static const _channel = MethodChannel('com.mintmusic/audio_effects');

  int? _sessionId;
  AudioEffectsConfig _config = const AudioEffectsConfig();
  Future<void> _pending = Future<void>.value();
  Stream<List<double>>? _visualizerStream;

  Future<void> setSessionId(int? sessionId) {
    _sessionId = sessionId;
    return _enqueueApply();
  }

  Future<void> apply(AudioEffectsConfig config) {
    _config = config;
    return _enqueueApply();
  }

  Future<void> _enqueueApply() {
    _pending = _pending.then((_) async {
      if (kIsWeb ||
          (defaultTargetPlatform != TargetPlatform.android &&
           defaultTargetPlatform != TargetPlatform.iOS)) {
        return;
      }
      try {
        await _channel.invokeMethod<void>('apply', {
          'sessionId': _sessionId,
          ..._config.toMap(),
        });
      } on MissingPluginException {
        // Desktop/test targets do not have the platform channel.
      } catch (error) {
        debugPrint('[AudioEffectService] apply failed: $error');
      }
    });
    return _pending;
  }

  Future<void> reset() => apply(const AudioEffectsConfig());

  Stream<List<double>> get visualizerStream => _visualizerStream ??=
      EventChannel('com.mintmusic/audio_effects/visualizer')
          .receiveBroadcastStream()
          .map(
            (event) =>
                (event as List).map((v) => (v as num).toDouble()).toList(),
          )
          .handleError((_) {});
}

final audioEffectService = AudioEffectService();
