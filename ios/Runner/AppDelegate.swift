import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // MintMusic platform channels (mirrors the Android MainActivity setup).
    let messenger = engineBridge.applicationRegistrar.messenger()
    MediaScannerHandler.register(with: messenger)
    TagWriterHandler.register(with: messenger)
    AudioEffectsHandler.register(with: messenger)
  }
}