import AVFoundation
import CoreMedia
import Flutter
import UIKit

/// iOS implementation of the `com.mintmusic/tag_writer` method channel.
///
/// Mirrors the Android `TagWriterHandler` semantics:
/// - `writeTags`             → title / artist / album / albumArtist / lyrics
/// - `writeArtwork`          → cover art only
/// - `writeTagsAndArtwork`   → both
///
/// AVFoundation can only *write* metadata to containers it can export
/// (MP3 via ID3, M4A/AAC via iTunes metadata). WAV is skipped with success,
/// exactly like the Android handler. FLAC/OGG/WMA cannot be rewritten by
/// AVFoundation, so they return an error that the Dart layer logs, keeping
/// the download pipeline alive.
class TagWriterHandler: NSObject {
    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "com.mintmusic/tag_writer",
            binaryMessenger: messenger
        )
        let handler = TagWriterHandler()
        channel.setMethodCallHandler(handler.handle)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "writeTags":
            handleWrite(
                call: call,
                result: result,
                includeTags: true,
                includeArtwork: false
            )
        case "writeArtwork":
            handleWrite(
                call: call,
                result: result,
                includeTags: false,
                includeArtwork: true
            )
        case "writeTagsAndArtwork":
            handleWrite(
                call: call,
                result: result,
                includeTags: true,
                includeArtwork: true
            )
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleWrite(
        call: FlutterMethodCall,
        result: @escaping FlutterResult,
        includeTags: Bool,
        includeArtwork: Bool
    ) {
        guard let args = call.arguments as? [String: Any],
              let filePath = args["filePath"] as? String,
              !filePath.isEmpty else {
            result(FlutterError(
                code: "NO_PATH",
                message: "filePath is null or empty",
                details: nil
            ))
            return
        }

        let fileURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath) else {
            result(FlutterError(
                code: "FILE_NOT_FOUND",
                message: "File does not exist: \(filePath)",
                details: nil
            ))
            return
        }

        let ext = (filePath as NSString).pathExtension.lowercased()
        if ext == "wav" {
            // Mirrors the Android handler: WAV tag writes are skipped.
            NSLog("[TagWriterHandler] skipping WAV file: %@", filePath)
            result(true)
            return
        }

        let tags: [String: String]
        if includeTags {
            tags = [
                "title": args["title"] as? String,
                "artist": args["artist"] as? String,
                "album": args["album"] as? String,
                "albumArtist": args["albumArtist"] as? String,
                "lyrics": args["lyrics"] as? String,
            ].compactMapValues { $0 }
        } else {
            tags = [:]
        }

        var artwork: Data?
        if includeArtwork {
            artwork = (args["artwork"] as? FlutterStandardTypedData)?.data
        }

        NSLog(
            "[TagWriterHandler] %@: filePath=%@ title=%@ artist=%@ album=%@ albumArtist=%@ hasLyrics=%d hasArtwork=%d",
            includeTags && includeArtwork ? "writeTagsAndArtwork"
                : includeTags ? "writeTags" : "writeArtwork",
            filePath,
            tags["title"] ?? "nil",
            tags["artist"] ?? "nil",
            tags["album"] ?? "nil",
            tags["albumArtist"] ?? "nil",
            tags["lyrics"] != nil ? 1 : 0,
            artwork != nil ? 1 : 0
        )

        writeMetadata(
            fileURL: fileURL,
            extension: ext,
            tags: tags,
            artwork: artwork,
            result: result
        )
    }

    // MARK: - AVFoundation metadata export

    /// Defines which metadata format a file extension maps to.
    private struct FormatInfo {
        let metadataFormat: AVMetadataFormat
        let outputFileType: AVFileType
        let identifierFor: (String) -> AVMetadataIdentifier
        let keySpace: AVMetadataKeySpace
    }

    private func formatInfo(for ext: String) -> FormatInfo? {
        switch ext {
        case "mp3":
            return FormatInfo(
                metadataFormat: .id3Metadata,
                outputFileType: .mp3,
                identifierFor: id3Identifier,
                keySpace: .id3
            )
        case "m4a", "aac", "mp4":
            return FormatInfo(
                metadataFormat: .iTunesMetadata,
                outputFileType: .m4a,
                identifierFor: itunesIdentifier,
                keySpace: .iTunes
            )
        default:
            // FLAC/OGG/WMA cannot be rewritten by AVFoundation.
            return nil
        }
    }

    private func id3Identifier(for field: String) -> AVMetadataIdentifier {
        switch field {
        case "title": return AVMetadataIdentifier(rawValue: "TIT2")
        case "artist": return AVMetadataIdentifier(rawValue: "TPE1")
        case "album": return AVMetadataIdentifier(rawValue: "TALB")
        case "albumArtist": return AVMetadataIdentifier(rawValue: "TPE2")
        case "lyrics": return AVMetadataIdentifier(rawValue: "USLT")
        case "artwork": return AVMetadataIdentifier(rawValue: "APIC")
        default: return AVMetadataIdentifier(rawValue: "TIT2")
        }
    }

    private func itunesIdentifier(for field: String) -> AVMetadataIdentifier {
        switch field {
        case "title": return AVMetadataIdentifier(rawValue: "©nam")
        case "artist": return AVMetadataIdentifier(rawValue: "©ART")
        case "album": return AVMetadataIdentifier(rawValue: "©alb")
        case "albumArtist": return AVMetadataIdentifier(rawValue: "aART")
        case "lyrics": return AVMetadataIdentifier(rawValue: "©lyr")
        case "artwork": return AVMetadataIdentifier(rawValue: "covr")
        default: return AVMetadataIdentifier(rawValue: "©nam")
        }
    }

    private func writeMetadata(
        fileURL: URL,
        extension ext: String,
        tags: [String: String],
        artwork: Data?,
        result: @escaping FlutterResult
    ) {
        guard let info = formatInfo(for: ext) else {
            NSLog(
                "[TagWriterHandler] unsupported format '.%@' on iOS (AVFoundation cannot rewrite it); skipping tag write",
                ext
            )
            result(FlutterError(
                code: "UNSUPPORTED_FORMAT",
                message: "AVFoundation cannot write metadata to .\(ext) files",
                details: nil
            ))
            return
        }

        let asset = AVURLAsset(url: fileURL)
        asset.loadValuesAsynchronously(forKeys: ["tracks", "availableMetadataFormats"]) {
            var loadError: NSError?
            let status = asset.statusOfValue(forKey: "tracks", error: &loadError)
            guard status == .loaded else {
                self.finish(
                    result: result,
                    error: FlutterError(
                        code: "LOAD_ERROR",
                        message: loadError?.localizedDescription ?? "Failed to load audio asset",
                        details: nil
                    )
                )
                return
            }

            // Merge: keep existing tags of this format that we are not
            // overwriting, then apply the new values. This preserves fields
            // like composer/genre/track number, matching jaudiotagger on
            // Android which only updates the provided fields.
            var items: [AVMetadataItem] = asset.metadata(forFormat: info.metadataFormat)
            items.removeAll { item in
                guard let id = item.identifier else { return false }
                return self.replacedIdentifiers(info: info).contains(id)
            }

            var newItems: [AVMutableMetadataItem] = []
            for (field, value) in tags {
                guard let item = self.makeItem(
                    info: info,
                    field: field,
                    value: value as NSString
                ) else { continue }
                newItems.append(item)
            }
            if let artwork = artwork, let item = self.makeArtworkItem(
                info: info,
                data: artwork
            ) {
                newItems.append(item)
            }

            // Nothing to write (e.g. empty tags and no artwork) — Android
            // skips silently in that case too.
            guard !newItems.isEmpty else {
                self.finish(result: result, success: true)
                return
            }

            self.export(
                asset: asset,
                items: items + newItems,
                info: info,
                originalURL: fileURL,
                result: result
            )
        }
    }

    private func replacedIdentifiers(info: FormatInfo) -> Set<AVMetadataIdentifier> {
        var ids: [AVMetadataIdentifier] = [
            info.identifierFor("title"),
            info.identifierFor("artist"),
            info.identifierFor("album"),
            info.identifierFor("albumArtist"),
            info.identifierFor("lyrics"),
            info.identifierFor("artwork"),
        ]
        // iTunes artwork historically uses the "covr" key with the "itsk"
        // key space; drop it explicitly so stale cover art is replaced.
        ids.append(AVMetadataIdentifier(rawValue: "covr"))
        return Set(ids)
    }

    private func makeItem(
        info: FormatInfo,
        field: String,
        value: NSString
    ) -> AVMutableMetadataItem? {
        let identifier = info.identifierFor(field)
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.key = identifier.rawValue as NSString
        item.keySpace = info.keySpace
        item.value = value
        item.dataType = "com.apple.metadata.datatype.utf8" as String
        return item
    }

    private func makeArtworkItem(
        info: FormatInfo,
        data: Data
    ) -> AVMutableMetadataItem? {
        let identifier = info.identifierFor("artwork")
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.key = identifier.rawValue as NSString
        item.keySpace = info.keySpace
        item.value = data as NSData
        item.dataType = "com.apple.metadata.datatype.data" as String
        return item
    }

    private func export(
        asset: AVURLAsset,
        items: [AVMetadataItem],
        info: FormatInfo,
        originalURL: URL,
        result: @escaping FlutterResult
    ) {
        let composition = AVMutableComposition()
        do {
            for track in asset.tracks {
                guard let compositionTrack = composition.addMutableTrack(
                    withMediaType: track.mediaType,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { continue }
                try compositionTrack.insertTimeRange(
                    track.timeRange,
                    of: track,
                    at: .zero
                )
            }
        } catch {
            finish(
                result: result,
                error: FlutterError(
                    code: "COMPOSE_ERROR",
                    message: error.localizedDescription,
                    details: nil
                )
            )
            return
        }

        // composition.metadata is get-only in newer iOS SDK; 
        // metadata is set on the export session instead (line below)

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            finish(
                result: result,
                error: FlutterError(
                    code: "EXPORT_SESSION_ERROR",
                    message: "Cannot create export session",
                    details: nil
                )
            )
            return
        }

        let tempURL = originalURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".\(UUID().uuidString).\(originalURL.pathExtension)"
            )
        session.outputURL = tempURL
        session.outputFileType = info.outputFileType
        session.metadata = items

        session.exportAsynchronously {
            switch session.status {
            case .completed:
                do {
                    try FileManager.default.replaceItemAt(
                        originalURL,
                        withItemAt: tempURL
                    )
                    try? FileManager.default.removeItem(at: tempURL)
                    self.finish(result: result, success: true)
                } catch {
                    try? FileManager.default.removeItem(at: tempURL)
                    self.finish(
                        result: result,
                        error: FlutterError(
                            code: "REPLACE_ERROR",
                            message: error.localizedDescription,
                            details: nil
                        )
                    )
                }
            case .failed, .cancelled:
                try? FileManager.default.removeItem(at: tempURL)
                self.finish(
                    result: result,
                    error: FlutterError(
                        code: "WRITE_METADATA_ERROR",
                        message: session.error?.localizedDescription
                            ?? "Metadata export failed",
                        details: nil
                    )
                )
            default:
                try? FileManager.default.removeItem(at: tempURL)
                self.finish(
                    result: result,
                    error: FlutterError(
                        code: "WRITE_METADATA_ERROR",
                        message: "Metadata export did not complete",
                        details: nil
                    )
                )
            }
        }
    }

    private func finish(result: @escaping FlutterResult, success: Bool) {
        DispatchQueue.main.async {
            result(success)
        }
    }

    private func finish(result: @escaping FlutterResult, error: FlutterError) {
        DispatchQueue.main.async {
            result(error)
        }
    }
}