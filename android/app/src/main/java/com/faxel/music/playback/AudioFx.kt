package com.faxel.music.playback

import android.content.Context
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.Visualizer
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/** Égaliseur, renfort des basses et spectre (visualiseur) branchés sur le lecteur. */
object AudioFx {
    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var visualizer: Visualizer? = null
    private var sessionId = 0
    private lateinit var appContext: Context

    var enabled by mutableStateOf(false)
        private set
    var bandCount by mutableStateOf(0)
        private set
    var bandFrequencies by mutableStateOf<List<Int>>(emptyList())
        private set
    var levels by mutableStateOf<List<Int>>(emptyList())
        private set
    var range by mutableStateOf(-1500..1500)
        private set
    var presets by mutableStateOf<List<String>>(emptyList())
        private set
    var preset by mutableStateOf(-1)
        private set
    var bass by mutableStateOf(0)
        private set

    /** Spectre 0…1 (32 bandes), rempli seulement quand le visualiseur réel est actif. */
    var spectrum by mutableStateOf(FloatArray(32))
        private set
    var spectrumLive by mutableStateOf(false)
        private set

    fun init(context: Context) {
        appContext = context.applicationContext
        val p = prefs()
        enabled = p.getBoolean("eqEnabled", false)
        bass = p.getInt("bass", 0)
        preset = p.getInt("preset", -1)
        levels = p.getString("levels", "")!!.split(',').mapNotNull { it.toIntOrNull() }
    }

    private fun prefs() = appContext.getSharedPreferences("audiofx", Context.MODE_PRIVATE)

    private fun save() {
        prefs().edit()
            .putBoolean("eqEnabled", enabled)
            .putInt("bass", bass)
            .putInt("preset", preset)
            .putString("levels", levels.joinToString(","))
            .apply()
    }

    fun attach(id: Int) {
        if (id == 0 || id == sessionId) return
        release()
        sessionId = id
        runCatching {
            val eq = Equalizer(0, id)
            equalizer = eq
            val count = eq.numberOfBands.toInt()
            bandCount = count
            val r = eq.bandLevelRange
            range = r[0].toInt()..r[1].toInt()
            bandFrequencies = (0 until count).map { eq.getCenterFreq(it.toShort()) / 1000 }
            presets = (0 until eq.numberOfPresets.toInt()).map { eq.getPresetName(it.toShort()) }
            if (levels.size != count) levels = List(count) { 0 }
            applyEqualizer()
        }
        runCatching {
            val boost = BassBoost(0, id)
            bassBoost = boost
            applyBass()
        }
    }

    fun release() {
        runCatching { equalizer?.release() }
        runCatching { bassBoost?.release() }
        stopVisualizer()
        equalizer = null
        bassBoost = null
        sessionId = 0
    }

    private fun applyEqualizer() {
        val eq = equalizer ?: return
        runCatching {
            eq.setEnabled(enabled)
            levels.forEachIndexed { band, level ->
                eq.setBandLevel(band.toShort(), level.coerceIn(range.first, range.last).toShort())
            }
        }
    }

    private fun applyBass() {
        val boost = bassBoost ?: return
        runCatching {
            boost.setEnabled(enabled && bass > 0)
            if (boost.strengthSupported) boost.setStrength(bass.toShort())
        }
    }

    @JvmName("updateEnabled")
    fun setEnabled(value: Boolean) {
        enabled = value
        applyEqualizer()
        applyBass()
        save()
    }

    fun setLevel(band: Int, level: Int) {
        if (band !in levels.indices) return
        levels = levels.toMutableList().also { it[band] = level }
        preset = -1
        if (!enabled) enabled = true
        applyEqualizer()
        applyBass()
        save()
    }

    fun usePreset(index: Int) {
        val eq = equalizer ?: return
        runCatching {
            eq.usePreset(index.toShort())
            levels = (0 until bandCount).map { eq.getBandLevel(it.toShort()).toInt() }
            preset = index
            enabled = true
            applyEqualizer()
            save()
        }
    }

    fun reset() {
        levels = List(bandCount) { 0 }
        preset = -1
        bass = 0
        applyEqualizer()
        applyBass()
        save()
    }

    @JvmName("updateBass")
    fun setBass(value: Int) {
        bass = value.coerceIn(0, 1000)
        if (bass > 0 && !enabled) enabled = true
        applyBass()
        save()
    }

    // MARK: Visualiseur (demande le micro : Android l'exige pour lire le spectre du son)

    fun startVisualizer() {
        if (visualizer != null || sessionId == 0) return
        runCatching {
            val v = Visualizer(sessionId)
            val sizes = Visualizer.getCaptureSizeRange()
            v.setCaptureSize(min(max(512, sizes[0]), sizes[1]))
            v.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(visualizer: Visualizer?, waveform: ByteArray?, samplingRate: Int) {}

                override fun onFftDataCapture(visualizer: Visualizer?, fft: ByteArray?, samplingRate: Int) {
                    val copy = fft?.copyOf() ?: return
                    main.post { spectrum = bands(copy, spectrum) }
                }
            }, min(Visualizer.getMaxCaptureRate(), 20000), false, true)
            v.setEnabled(true)
            visualizer = v
            spectrumLive = true
        }
    }

    fun stopVisualizer() {
        runCatching {
            visualizer?.setEnabled(false)
            visualizer?.release()
        }
        visualizer = null
        spectrumLive = false
        spectrum = FloatArray(32)
    }

    private var peak = 1f
    private val main = android.os.Handler(android.os.Looper.getMainLooper())

    private fun bands(fft: ByteArray, previous: FloatArray): FloatArray {
        val half = fft.size / 2
        val out = FloatArray(32)
        for (band in 0 until 32) {
            val low = max(1, (half.toDouble().pow(band / 32.0)).toInt())
            val high = max(low + 1, (half.toDouble().pow((band + 1) / 32.0)).toInt()).coerceAtMost(half)
            var sum = 0f
            var count = 0
            for (bin in low until high) {
                val re = fft[2 * bin].toFloat()
                val im = fft[2 * bin + 1].toFloat()
                sum += hypot(re, im)
                count++
            }
            out[band] = if (count > 0) ln(1f + sum / count) else 0f
        }
        val loudest = out.maxOrNull() ?: 0f
        peak = max(peak * 0.995f, max(loudest, 0.001f))
        for (i in out.indices) {
            val value = (out[i] / peak).coerceIn(0f, 1f)
            out[i] = if (value > previous[i]) value else previous[i] * 0.8f + value * 0.2f
        }
        return out
    }
}
