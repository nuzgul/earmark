package app.earmark.recorder.engine

import java.io.DataInputStream
import java.io.EOFException
import java.io.InputStream

/**
 * ADTS framing for the crash-safe `audio.aac.part` stream: every AAC frame carries its own
 * 7-byte header, so a file cut off by a crash is readable up to its last whole frame.
 * Pure Kotlin (no Android types) so it is covered by JVM tests.
 */
object Adts {
    const val HEADER = 7
    const val SAMPLES_PER_FRAME = 1024
    private val RATES = intArrayOf(96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350)

    fun rateIndex(sampleRate: Int): Int = RATES.indexOf(sampleRate).also { require(it >= 0) { "unsupported rate $sampleRate" } }

    fun rateAt(index: Int): Int = RATES[index]

    /** Header for one AAC-LC frame whose payload is [payloadLen] bytes (no CRC). */
    fun header(payloadLen: Int, sampleRate: Int, channels: Int): ByteArray {
        val len = payloadLen + HEADER
        val idx = rateIndex(sampleRate)
        return byteArrayOf(
            0xFF.toByte(),
            0xF1.toByte(), // MPEG-4, layer 0, no CRC
            ((1 shl 6) or (idx shl 2) or (channels shr 2)).toByte(), // profile LC (2-1)
            (((channels and 3) shl 6) or (len shr 11)).toByte(),
            ((len shr 3) and 0xFF).toByte(),
            (((len and 7) shl 5) or 0x1F).toByte(),
            0xFC.toByte(),
        )
    }

    /** AudioSpecificConfig (csd-0) for MediaMuxer. */
    fun audioSpecificConfig(sampleRate: Int, channels: Int): ByteArray {
        val v = (2 shl 11) or (rateIndex(sampleRate) shl 7) or (channels shl 3)
        return byteArrayOf((v shr 8).toByte(), v.toByte())
    }

    data class Format(val sampleRate: Int, val channels: Int)

    /**
     * Streams whole frames from [input] to [onFrame] (payload only, header stripped) and stops at
     * the first damaged or truncated frame. Returns the stream format, or null if it holds no frame.
     */
    fun readFrames(input: InputStream, onFrame: (Format, ByteArray) -> Unit): Format? {
        val data = DataInputStream(input)
        val h = ByteArray(HEADER)
        var format: Format? = null
        while (true) {
            try {
                data.readFully(h)
                if (h[0] != 0xFF.toByte() || (h[1].toInt() and 0xF0) != 0xF0) break
                val b2 = h[2].toInt() and 0xFF
                val b3 = h[3].toInt() and 0xFF
                val len = ((b3 and 3) shl 11) or ((h[4].toInt() and 0xFF) shl 3) or ((h[5].toInt() and 0xFF) shr 5)
                val headerLen = if (h[1].toInt() and 1 == 0) HEADER + 2 else HEADER // CRC present
                if (len <= headerLen || (b2 shr 2) and 0xF >= RATES.size) break
                if (headerLen > HEADER) data.readFully(ByteArray(2))
                val payload = ByteArray(len - headerLen)
                data.readFully(payload)
                val f = format ?: Format(rateAt((b2 shr 2) and 0xF), ((b2 and 1) shl 2) or (b3 shr 6)).also { format = it }
                onFrame(f, payload)
            } catch (_: EOFException) {
                break
            }
        }
        return format
    }

    fun framesToMs(frames: Long, sampleRate: Int): Long = frames * 1000 / sampleRate
}
