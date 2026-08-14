package com.kingmc.mintmusic.mintmusic

import android.content.Context
import android.graphics.BitmapFactory
import android.media.MediaScannerConnection
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.jaudiotagger.audio.AudioFileIO
import org.jaudiotagger.audio.flac.metadatablock.MetadataBlockDataPicture
import org.jaudiotagger.tag.FieldKey
import org.jaudiotagger.tag.flac.FlacTag
import org.jaudiotagger.tag.images.AndroidArtwork
import org.jaudiotagger.tag.reference.PictureTypes
import java.io.File

class TagWriterHandler(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "TagWriterHandler"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "writeTags" -> handleWriteTags(call, result)
            "writeArtwork" -> handleWriteArtwork(call, result)
            "writeTagsAndArtwork" -> handleWriteTagsAndArtwork(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleWriteTags(call: MethodCall, result: MethodChannel.Result) {
        try {
            val filePath = call.argument<String>("filePath") ?: run {
                result.error("NO_PATH", "filePath is null", null)
                return
            }
            val title = call.argument<String>("title")
            val artist = call.argument<String>("artist")
            val album = call.argument<String>("album")
            val albumArtist = call.argument<String>("albumArtist")
            val lyrics = call.argument<String>("lyrics")

            Log.d(TAG, "writeTags: filePath=$filePath, title=$title, artist=$artist, album=$album, albumArtist=$albumArtist, hasLyrics=${lyrics != null}")

            val file = File(filePath)
            if (!file.exists()) {
                Log.e(TAG, "writeTags: file not found: $filePath")
                result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
                return
            }

            val ext = filePath.substring(filePath.lastIndexOf('.')).lowercase()
            if (ext == ".wav") {
                Log.d(TAG, "writeTags: skipping WAV file")
                result.success(true)
                return
            }

            val audioFile = AudioFileIO.read(file)
            val existingTag = audioFile.tagOrCreateAndSetDefault

            Log.d(TAG, "writeTags: tag class=${existingTag.javaClass.simpleName}")

            writeTagFields(existingTag, title, artist, album, albumArtist, lyrics)

            AudioFileIO.write(audioFile)
            Log.d(TAG, "writeTags: successfully wrote tags to $filePath")
            scanFile(filePath)

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "writeTags error: ${e.message}", e)
            result.error("WRITE_TAGS_ERROR", e.message, e.toString())
        }
    }

    private fun handleWriteArtwork(call: MethodCall, result: MethodChannel.Result) {
        try {
            val filePath = call.argument<String>("filePath") ?: run {
                result.error("NO_PATH", "filePath is null", null)
                return
            }
            val artworkData = call.argument<ByteArray>("artwork") ?: run {
                result.error("NO_ARTWORK", "artwork is null", null)
                return
            }

            Log.d(TAG, "writeArtwork: filePath=$filePath, artworkSize=${artworkData.size}")

            val file = File(filePath)
            if (!file.exists()) {
                Log.e(TAG, "writeArtwork: file not found: $filePath")
                result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
                return
            }

            val ext = filePath.substring(filePath.lastIndexOf('.')).lowercase()
            if (ext == ".wav") {
                Log.d(TAG, "writeArtwork: skipping WAV file")
                result.success(true)
                return
            }

            val audioFile = AudioFileIO.read(file)
            val tag = audioFile.tagOrCreateAndSetDefault
            val mimeType = detectMimeType(artworkData)

            Log.d(TAG, "writeArtwork: tag class=${tag.javaClass.simpleName}, mime=$mimeType")

            if (tag is FlacTag) {
                writeFlacPicture(tag, artworkData, mimeType)
            } else {
                val artwork = AndroidArtwork()
                artwork.setBinaryData(artworkData)
                artwork.setMimeType(mimeType)
                artwork.setPictureType(PictureTypes.DEFAULT_ID)
                tag.deleteArtworkField()
                tag.setField(artwork)
            }

            audioFile.setTag(tag)
            AudioFileIO.write(audioFile)
            Log.d(TAG, "writeArtwork: successfully wrote artwork to $filePath")
            scanFile(filePath)

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "writeArtwork error: ${e.message}", e)
            result.error("WRITE_ARTWORK_ERROR", e.message, e.toString())
        }
    }

    private fun handleWriteTagsAndArtwork(call: MethodCall, result: MethodChannel.Result) {
        try {
            val filePath = call.argument<String>("filePath") ?: run {
                result.error("NO_PATH", "filePath is null", null)
                return
            }
            val title = call.argument<String>("title")
            val artist = call.argument<String>("artist")
            val album = call.argument<String>("album")
            val albumArtist = call.argument<String>("albumArtist")
            val lyrics = call.argument<String>("lyrics")
            val artworkData = call.argument<ByteArray>("artwork")

            Log.d(TAG, "writeTagsAndArtwork: filePath=$filePath, title=$title, artist=$artist, album=$album, albumArtist=$albumArtist, hasLyrics=${lyrics != null}, hasArtwork=${artworkData != null}")

            val file = File(filePath)
            if (!file.exists()) {
                Log.e(TAG, "writeTagsAndArtwork: file not found: $filePath")
                result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
                return
            }

            val ext = filePath.substring(filePath.lastIndexOf('.')).lowercase()
            if (ext == ".wav") {
                Log.d(TAG, "writeTagsAndArtwork: skipping WAV file")
                result.success(true)
                return
            }

            val audioFile = AudioFileIO.read(file)
            val tag = audioFile.tagOrCreateAndSetDefault

            Log.d(TAG, "writeTagsAndArtwork: tag class=${tag.javaClass.simpleName}")

            writeTagFields(tag, title, artist, album, albumArtist, lyrics)

            if (artworkData != null) {
                val mimeType = detectMimeType(artworkData)
                if (tag is FlacTag) {
                    writeFlacPicture(tag, artworkData, mimeType)
                    Log.d(TAG, "writeTagsAndArtwork: artwork added via FlacTag (mime=$mimeType)")
                } else {
                    val artwork = AndroidArtwork()
                    artwork.setBinaryData(artworkData)
                    artwork.setMimeType(mimeType)
                    artwork.setPictureType(PictureTypes.DEFAULT_ID)
                    tag.deleteArtworkField()
                    tag.setField(artwork)
                    Log.d(TAG, "writeTagsAndArtwork: artwork attached (mime=$mimeType)")
                }
            }

            audioFile.setTag(tag)
            AudioFileIO.write(audioFile)
            Log.d(TAG, "writeTagsAndArtwork: successfully wrote to $filePath")
            scanFile(filePath)

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "writeTagsAndArtwork error: ${e.message}", e)
            result.error("WRITE_TAGS_ARTWORK_ERROR", e.message, e.toString())
        }
    }

    private fun writeTagFields(
        tag: org.jaudiotagger.tag.Tag,
        title: String?,
        artist: String?,
        album: String?,
        albumArtist: String?,
        lyrics: String?
    ) {
        try {
            if (title != null) {
                tag.deleteField(FieldKey.TITLE)
                tag.addField(FieldKey.TITLE, title)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to write title: ${e.message}")
        }
        try {
            if (artist != null) {
                tag.deleteField(FieldKey.ARTIST)
                tag.addField(FieldKey.ARTIST, artist)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to write artist: ${e.message}")
        }
        try {
            if (album != null) {
                tag.deleteField(FieldKey.ALBUM)
                tag.addField(FieldKey.ALBUM, album)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to write album: ${e.message}")
        }
        try {
            if (albumArtist != null) {
                tag.deleteField(FieldKey.ALBUM_ARTIST)
                tag.addField(FieldKey.ALBUM_ARTIST, albumArtist)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to write albumArtist: ${e.message}")
        }
        try {
            if (lyrics != null) {
                tag.deleteField(FieldKey.LYRICS)
                tag.addField(FieldKey.LYRICS, lyrics)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to write lyrics: ${e.message}")
        }
    }

    private fun writeFlacPicture(tag: FlacTag, artworkData: ByteArray, mimeType: String) {
        val opts = BitmapFactory.Options()
        opts.inJustDecodeBounds = true
        BitmapFactory.decodeByteArray(artworkData, 0, artworkData.size, opts)
        val width = if (opts.outWidth > 0) opts.outWidth else 300
        val height = if (opts.outHeight > 0) opts.outHeight else 300
        val colourDepth = if (mimeType == "image/png") 32 else 24
        val picture = MetadataBlockDataPicture(
            artworkData,
            PictureTypes.DEFAULT_ID,
            mimeType,
            "",
            width,
            height,
            colourDepth,
            0
        )
        val images = tag.images
        images.clear()
        images.add(picture)
        Log.d(TAG, "writeFlacPicture: added picture ${width}x${height} depth=$colourDepth")
    }

    private fun detectMimeType(data: ByteArray): String {
        if (data.size < 4) return "image/jpeg"
        if (data[0] == 0x89.toByte() && data[1] == 0x50.toByte() && data[2] == 0x4E.toByte() && data[3] == 0x47.toByte()) return "image/png"
        if (data[0] == 0x47.toByte() && data[1] == 0x49.toByte() && data[2] == 0x46.toByte() && data[3] == 0x38.toByte()) return "image/gif"
        if (data[0] == 0x52.toByte() && data[1] == 0x49.toByte() && data[2] == 0x46.toByte() && data[3] == 0x46.toByte()) return "image/webp"
        return "image/jpeg"
    }

    private fun scanFile(path: String) {
        try {
            MediaScannerConnection.scanFile(context, arrayOf(path), null, null)
        } catch (_: Exception) {
            Log.w(TAG, "MediaScannerConnection.scanFile failed")
        }
    }
}