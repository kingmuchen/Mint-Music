package com.kingmc.mintmusic.mintmusic

import android.content.Intent
import android.media.MediaScannerConnection
import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.Equalizer
import android.media.audiofx.Virtualizer
import android.media.audiofx.Visualizer
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import com.ryanheise.audioservice.AudioServiceActivity
import java.io.File

class MainActivity : AudioServiceActivity() {
    private val MEDIA_CHANNEL = "com.mintmusic/media"
    private val TAG_WRITER_CHANNEL = "com.mintmusic/tag_writer"
    private val AUDIO_EFFECTS_CHANNEL = "com.mintmusic/audio_effects"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanFile" -> {
                        val path = call.arguments as? String ?: ""
                        if (path.isNotEmpty()) {
                            MediaScannerConnection.scanFile(this, arrayOf(path), null, null)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARG", "path is empty", null)
                        }
                    }
                    "openManageStorageSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TAG_WRITER_CHANNEL)
            .setMethodCallHandler(TagWriterHandler(this))

        val audioEffectsHandler = AudioEffectsHandler()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_EFFECTS_CHANNEL)
            .setMethodCallHandler(audioEffectsHandler)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "$AUDIO_EFFECTS_CHANNEL/visualizer")
            .setStreamHandler(audioEffectsHandler)
    }

    private inner class AudioEffectsHandler : MethodChannel.MethodCallHandler,
        EventChannel.StreamHandler {
        private var sessionId: Int? = null
        private var visualizerEnabled = false
        private var visualizer: Visualizer? = null
        private var eventSink: EventChannel.EventSink? = null
        private var equalizer: Equalizer? = null
        private var bassBoost: BassBoost? = null
        private var virtualizer: Virtualizer? = null
        private var balance: DynamicsProcessing? = null

        // A DynamicsProcessing engine with every built-in stage (PreEQ, MBC,
        // PostEQ, limiter) disabled from the start. Constructing with `null`
        // enables the default engine: a 6-band MBC (-60dB threshold) plus a
        // -3dB peak limiter which squash/amplify the whole signal into harsh
        // clipping ("麦很炸"). setAllChannelsTo() afterwards cannot tear down
        // stages the engine architecture already enabled at construction time,
        // so the transparent config must be passed in the constructor. Balance
        // only adjusts per-channel input gain (millibels, dB * 100).
        private val transparentDpConfig: DynamicsProcessing.Config by lazy {
            DynamicsProcessing.Config.Builder(
                DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                1, // replicated to the real channel count by the constructor
                false, 0, // pre-EQ off
                false, 0, // MBC off
                false, 0, // post-EQ off
                false,    // limiter off
            ).build()
        }

        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
            when (call.method) {
                "apply" -> {
                    try {
                        val previousSessionId = sessionId
                        sessionId = (call.argument<Number>("sessionId"))?.toInt()
                        if (previousSessionId != sessionId) releaseEffects()
                        applyEffects(call)
                        result.success(true)
                    } catch (error: Throwable) {
                        // AudioEffect support varies by vendor and by output route.
                        // A failed effect must never make playback fail.
                        releaseEffects()
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
            if (visualizerEnabled) startVisualizerIfNeeded()
        }

        override fun onCancel(arguments: Any?) {
            eventSink = null
            release(visualizer)
            visualizer = null
        }

        private fun applyEffects(call: MethodCall) {
            val id = sessionId ?: run {
                releaseEffects()
                return
            }
            val master = call.argument<Boolean>("masterEnabled") == true
            visualizerEnabled = call.argument<Boolean>("visualizerEnabled") == true

            if (visualizerEnabled) startVisualizerIfNeeded() else {
                release(visualizer)
                visualizer = null
            }

            // Effects are created lazily once per audio session and afterwards
            // stay attached AND enabled for the whole session. Turning an effect
            // on/off only changes its parameters, never `enabled`: toggling
            // `enabled` on a live session makes the audio HAL bypass/insert the
            // effect and reconfigure the whole effect chain, which produces a
            // loud transient burst ("关闭瞬间声音突然增大"), worse when several
            // effects are attached. Neutral parameters (flat EQ, 0 bass, 0
            // surround, 0dB balance) are transparent, so "off" needs no bypass.
            // This mirrors the reference players (CeruMusic / Mio-Music), which
            // build their audio graph once and only change node parameter
            // values.
            applyEqualizer(call, id, master)
            applyBassBoost(call, id, master)
            applySurround(call, id, master)
            applyBalance(call, id, master)
        }

        private fun applyEqualizer(call: MethodCall, id: Int, master: Boolean) {
            val enabled = master && call.argument<Boolean>("equalizerEnabled") == true
            try {
                val eq = equalizer ?: if (enabled) {
                    Equalizer(0, id).also { equalizer = it }
                } else return
                val range = eq.bandLevelRange
                val bands = call.argument<List<*>>("equalizerBands").orEmpty()
                for (index in 0 until minOf(eq.numberOfBands.toInt(), bands.size)) {
                    // "Off" is a flat EQ (0dB every band) on the same instance.
                    val gainDb = if (enabled) (bands[index] as? Number)?.toDouble() ?: 0.0 else 0.0
                    val level = (gainDb * 100.0).toInt().coerceIn(range[0].toInt(), range[1].toInt())
                    eq.setBandLevel(index.toShort(), level.toShort())
                }
                eq.enabled = true
            } catch (_: Throwable) {
                release(equalizer)
                equalizer = null
            }
        }

        private fun applyBassBoost(call: MethodCall, id: Int, master: Boolean) {
            val enabled = master && call.argument<Boolean>("bassBoostEnabled") == true
            try {
                val bass = bassBoost ?: if (enabled) {
                    BassBoost(0, id).also { bassBoost = it }
                } else return
                if (bass.strengthSupported) {
                    // "Off" is strength 0 (no boost) on the same instance.
                    val strength = if (enabled) {
                        val gain = (call.argument<Number>("bassBoostGain")?.toDouble() ?: 0.0)
                            .coerceIn(0.0, 12.0)
                        (gain / 12.0 * 1000.0).toInt()
                    } else 0
                    bass.setStrength(strength.toShort())
                }
                bass.enabled = true
            } catch (_: Throwable) {
                release(bassBoost)
                bassBoost = null
            }
        }

        private fun applySurround(call: MethodCall, id: Int, master: Boolean) {
            val enabled = master && call.argument<Boolean>("surroundEnabled") == true
            try {
                val surround = virtualizer ?: if (enabled) {
                    Virtualizer(0, id).also { virtualizer = it }
                } else return
                if (surround.strengthSupported) {
                    // "Off" is strength 0 on the same instance, never a bypass.
                    // The reference players mix a reverb wet signal on top of
                    // the dry one and never raise the overall level; very high
                    // Virtualizer strengths are known to push loudness/clipping
                    // on many devices, so the strengths are capped lower.
                    val strength = when {
                        !enabled -> 0
                        call.argument<String>("surroundMode") == "large" -> 700
                        call.argument<String>("surroundMode") == "medium" -> 500
                        else -> 300
                    }
                    surround.setStrength(strength.toShort())
                }
                surround.enabled = true
            } catch (_: Throwable) {
                release(virtualizer)
                virtualizer = null
            }
        }

        private fun applyBalance(call: MethodCall, id: Int, master: Boolean) {
            val enabled = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P &&
                master && call.argument<Boolean>("balanceEnabled") == true
            try {
                val dp = balance ?: if (enabled) {
                    DynamicsProcessing(0, id, transparentDpConfig).also { balance = it }
                } else return
                val value = (call.argument<Number>("balance")?.toDouble() ?: 0.0)
                    .coerceIn(-1.0, 1.0)
                // Same semantics as the reference player: only the opposite
                // channel is attenuated (never boosted). "Off" is 0dB on both
                // channels of the same instance. The gain unit is millibels,
                // so decibels must be multiplied by 100.
                val leftDb = if (enabled && value > 0) -24.0 * value else 0.0
                val rightDb = if (enabled && value < 0) 24.0 * value else 0.0
                val channels = dp.getChannelCount()
                if (channels > 0) {
                    dp.setInputGainbyChannel(0, (leftDb * 100.0).toFloat())
                }
                if (channels > 1) {
                    dp.setInputGainbyChannel(1, (rightDb * 100.0).toFloat())
                }
                dp.enabled = true
            } catch (_: Throwable) {
                release(balance)
                balance = null
            }
        }

        // Effects are only released when the audio session changes or an error
        // occurs, never on a setting toggle (toggles are parameter-only).
        // Disabling an effect before releasing it is still required: a
        // release() on an enabled effect can leave the instance attached to the
        // audio session.
        private fun release(effect: AudioEffect?) {
            if (effect == null) return
            try { effect.enabled = false } catch (_: Throwable) { }
            try { effect.release() } catch (_: Throwable) { }
        }

        private fun release(effect: Visualizer?) {
            if (effect == null) return
            try { effect.enabled = false } catch (_: Throwable) { }
            try { effect.release() } catch (_: Throwable) { }
        }

        private fun releaseEffects() {
            release(visualizer)
            release(equalizer)
            release(bassBoost)
            release(virtualizer)
            release(balance)
            equalizer = null
            bassBoost = null
            virtualizer = null
            balance = null
            visualizer = null
        }

        private fun startVisualizerIfNeeded() {
            val id = sessionId ?: return
            if (eventSink == null || visualizer != null) return
            try {
                val captureSize = Visualizer.getCaptureSizeRange()[1].coerceAtMost(512)
                val v = Visualizer(id)
                v.captureSize = captureSize
                v.scalingMode = Visualizer.SCALING_MODE_NORMALIZED
                v.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        visualizer: Visualizer?, waveform: ByteArray?, samplingRate: Int
                    ) = Unit

                    override fun onFftDataCapture(
                        visualizer: Visualizer?, fft: ByteArray?, samplingRate: Int
                    ) {
                        val sink = eventSink ?: return
                        val data = fft ?: return
                        val bars = ArrayList<Double>(32)
                        val binCount = minOf(32, data.size / 2)
                        for (index in 0 until binCount) {
                            val real = data[index * 2].toInt()
                            val imaginary = data[index * 2 + 1].toInt()
                            val magnitude = kotlin.math.sqrt(
                                (real * real + imaginary * imaginary).toDouble()
                            ) / 181.0
                            bars.add(magnitude.coerceIn(0.0, 1.0))
                        }
                        runOnUiThread { sink.success(bars) }
                    }
                }, Visualizer.getMaxCaptureRate() / 3, false, true)
                v.enabled = true
                visualizer = v
            } catch (_: Throwable) {
                release(visualizer)
                visualizer = null
            }
        }
    }
}
