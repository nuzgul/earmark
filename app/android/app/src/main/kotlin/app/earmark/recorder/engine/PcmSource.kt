package app.earmark.recorder.engine

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.SystemClock
import kotlin.math.PI
import kotlin.math.sin

/** Where PCM comes from: the microphone, or (tests only) a tone paced by the real clock. */
interface PcmSource {
    /** Audio session id, for matching recording callbacks; 0 when not a real recorder. */
    val sessionId: Int

    fun start(): Boolean

    /** Blocking read of up to [n] mono frames; negative on error. */
    fun read(buf: ShortArray, n: Int): Int

    fun release()
}

class MicSource private constructor(private val r: AudioRecord) : PcmSource {
    override val sessionId get() = r.audioSessionId

    override fun start(): Boolean {
        r.startRecording()
        return r.recordingState == AudioRecord.RECORDSTATE_RECORDING
    }

    override fun read(buf: ShortArray, n: Int) = r.read(buf, 0, n)

    override fun release() {
        runCatching { r.stop() }
        r.release()
    }

    companion object {
        private const val MONO = AudioFormat.CHANNEL_IN_MONO
        private const val PCM16 = AudioFormat.ENCODING_PCM_16BIT

        fun supports(rate: Int) = AudioRecord.getMinBufferSize(rate, MONO, PCM16) > 0

        @SuppressLint("MissingPermission") // checked by the caller before start()
        fun open(rate: Int): MicSource? {
            val min = AudioRecord.getMinBufferSize(rate, MONO, PCM16)
            // ~4 s rides out a capture thread held up by storage; the old 0.5 s is the fallback
            // for a phone that refuses a buffer that large.
            for (bytes in intArrayOf(maxOf(min, rate * 2 * 4), maxOf(min * 4, rate))) {
                val r = try {
                    AudioRecord(MediaRecorder.AudioSource.MIC, rate, MONO, PCM16, bytes)
                } catch (_: Exception) {
                    continue
                }
                if (r.state == AudioRecord.STATE_INITIALIZED) return MicSource(r)
                r.release()
            }
            return null
        }
    }
}

/**
 * Test source (debug builds only). Delivers exactly as many frames as real time allows, so a test
 * can check timing without the emulator's unreliable microphone clock. The pitch encodes the
 * second of audio (300 Hz + 20 Hz × second), which lets a test prove what a clip contains.
 */
class ToneSource(private val rate: Int) : PcmSource {
    override val sessionId = 0
    private var startNs = 0L
    private var produced = 0L
    private var phase = 0.0

    override fun start(): Boolean {
        startNs = SystemClock.elapsedRealtimeNanos()
        return true
    }

    override fun read(buf: ShortArray, n: Int): Int {
        val due = produced + n
        val waitNs = due * 1_000_000_000L / rate - (SystemClock.elapsedRealtimeNanos() - startNs)
        if (waitNs > 0) SystemClock.sleep(waitNs / 1_000_000 + 1)
        for (i in 0 until n) {
            val hz = 300.0 + 20.0 * ((produced + i) / rate)
            phase += 2 * PI * hz / rate
            buf[i] = (sin(phase) * 8000).toInt().toShort()
        }
        produced = due
        return n
    }

    override fun release() {}
}
