import Flutter
import UIKit

/// iOS implementation of the `com.mintmusic/media` method channel.
///
/// Mirrors the Android `MainActivity` handler semantics:
/// - `scanFile`: on Android this pokes `MediaScannerConnection` so the
///   downloaded file appears in the system media store. iOS apps download
///   into their own sandbox and there is no equivalent media-store scan
///   step, so this is a successful no-op.
/// - `openManageStorageSettings`: Android-only "All files access" settings
///   screen; not applicable on iOS, so it reports false like a device that
///   does not need it.
class MediaScannerHandler: NSObject, FlutterMethodCallHandler {
    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "com.mintmusic/media",
            binaryMessenger: messenger
        )
        let handler = MediaScannerHandler()
        channel.setMethodCallHandler(handler.handle)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "scanFile":
            // Files written by the app live in its own sandbox (Documents),
            // so there is no media store scan required on iOS.
            result(true)
        case "openManageStorageSettings":
            // iOS has no equivalent of the "manage all files" settings
            // screen; the sandboxed Documents directory is always writable.
            result(false)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}