package app.earmark.recorder.engine

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Lossless clip: copies the AAC frames of a time range into a new .m4a (no re-encode). */
object ClipExporter {
    private const val KEEP_MS = 24 * 3600 * 1000L

    /**
     * Copies [startMs, endMs) of `folder/audio.m4a` into [outDir]/[fileName]. Accurate to one AAC
     * frame (~21 ms). The source is only read. Clips older than 24 h in [outDir] are removed.
     */
    fun export(folder: File, startMs: Long, endMs: Long, fileName: String, outDir: File): File {
        require(endMs > startMs) { "empty range" }
        outDir.mkdirs()
        val now = System.currentTimeMillis()
        outDir.listFiles().orEmpty().filter { now - it.lastModified() > KEEP_MS }.forEach { it.delete() }

        val safe = fileName.replace(Regex("[\\\\/:*?\"<>|\\n\\r]"), "-").take(120).ifBlank { "clip.m4a" }
        val out = File(outDir, safe)
        val tmp = File(outDir, "$safe.tmp")
        val ex = MediaExtractor()
        var written = 0
        try {
            ex.setDataSource(File(folder, Finalizer.AUDIO).path)
            ex.selectTrack(0)
            val format = ex.getTrackFormat(0)
            val muxer = MediaMuxer(tmp.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            try {
                val track = muxer.addTrack(format)
                muxer.start()
                ex.seekTo(startMs * 1000, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                val buf = ByteBuffer.allocate(64 * 1024)
                val info = MediaCodec.BufferInfo()
                var first = -1L
                while (true) {
                    val n = ex.readSampleData(buf, 0)
                    if (n < 0 || ex.sampleTime >= endMs * 1000) break
                    if (first < 0) first = ex.sampleTime
                    info.set(0, n, ex.sampleTime - first, MediaCodec.BUFFER_FLAG_KEY_FRAME)
                    muxer.writeSampleData(track, buf, info)
                    written++
                    ex.advance()
                }
                if (written > 0) muxer.stop()
            } finally {
                muxer.release()
            }
        } finally {
            ex.release()
        }
        check(written > 0) { "nothing to export in that range" }
        out.delete()
        check(tmp.renameTo(out)) { "could not write the clip" }
        return out
    }
}

/** Debug builds only: facts about an audio file that tests check (duration, test-tone pitch). */
object AudioProbe {
    /** Pitch is measured from 0.1 s to 0.35 s, past the encoder's priming. */
    fun probe(path: String): AudioProbeResult {
        val ex = MediaExtractor()
        ex.setDataSource(path)
        ex.selectTrack(0)
        val format = ex.getTrackFormat(0)
        val rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val durationMs = format.getLong(MediaFormat.KEY_DURATION) / 1000
        val dec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        dec.configure(format, null, null, 0)
        dec.start()
        val need = rate * 35 / 100
        val pcm = ShortArray(need)
        var have = 0
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        try {
            while (have < need) {
                if (!inputDone) {
                    val i = dec.dequeueInputBuffer(10_000)
                    if (i >= 0) {
                        val n = ex.readSampleData(dec.getInputBuffer(i)!!, 0)
                        if (n < 0) {
                            dec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            dec.queueInputBuffer(i, 0, n, ex.sampleTime, 0)
                            ex.advance()
                        }
                    }
                }
                val o = dec.dequeueOutputBuffer(info, 10_000)
                if (o >= 0) {
                    val shorts = dec.getOutputBuffer(o)!!.order(ByteOrder.nativeOrder()).asShortBuffer()
                    val take = minOf(shorts.remaining(), need - have)
                    shorts.get(pcm, have, take)
                    have += take
                    dec.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        } finally {
            dec.stop()
            dec.release()
            ex.release()
        }
        val from = rate / 10
        var rises = 0
        for (i in from + 1 until have) if (pcm[i - 1] < 0 && pcm[i] >= 0) rises++
        val seconds = (have - from - 1).toDouble() / rate
        return AudioProbeResult(durationMs, if (seconds > 0) rises / seconds else 0.0)
    }
}
