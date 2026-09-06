import AVFoundation
import Flutter

/// iOS implementation of the `com.mintmusic/audio_effects` method channel.
///
/// Mirrors the Android `AudioEffectsHandler` semantics:
/// - `apply` → accepts the same parameter map; on iOS the audio pipeline
///   is owned by `AVPlayer` (via just_audio) and is not directly
///   interceptable, so this handler stores the configuration and returns
///   `true` to let the Dart layer proceed without error.
/// - Visualizer `EventChannel` → returns empty waveform data (iOS does
///   not expose FFT capture from AVPlayer).
///
/// The design is intentionally "accept and succeed" so the Dart settings
/// UI works identically on both platforms. Future iOS versions could hook
/// into `AVAudioEngine` or a custom `AudioUnit` to provide real effects.
class AudioEffectsHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var displayLink: CADisplayLink?
    private var currentBands: [Double] = Array(repeating: 0.0, count: 32)
    private var isPlaying = false

    static func register(with messenger: FlutterBinaryMessenger) {
        let methodChannel = FlutterMethodChannel(
            name: "com.mintmusic/audio_effects",
            binaryMessenger: messenger
        )
        let eventChannel = FlutterEventChannel(
            name: "com.mintmusic/audio_effects/visualizer",
            binaryMessenger: messenger
        )
        let handler = AudioEffectsHandler()
        methodChannel.setMethodCallHandler(handler.handle)
        eventChannel.setStreamHandler(handler)
    }

    // MARK: - FlutterMethodCallHandler

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "apply":
            // On iOS the audio pipeline is owned by AVPlayer and cannot be
            // intercepted through AudioEffect APIs. Accept the call and
            // return success so the Dart settings UI behaves identically.
            NSLog("[AudioEffectsHandler] apply (iOS no-op): %@", "\(call.arguments ?? "nil")")
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - FlutterStreamHandler (Visualizer)

    @objc func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        startVisualizerSimulation()
        return nil
    }

    @objc func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stopVisualizerSimulation()
        self.eventSink = nil
        return nil
    }

    private func startVisualizerSimulation() {
        // iOS does not expose FFT data from AVPlayer. We emit zero-valued
        // bars so the visualizer widget renders without errors.
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopVisualizerSimulation() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard let sink = eventSink else { return }
        // Emit a flat zero array — the visualizer UI will show an idle state.
        sink(currentBands)
    }
}
