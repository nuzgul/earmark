package app.earmark.recorder.engine

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/** Turns a session folder's crash-safe ADTS stream into the final audio.m4a (no re-encode). */
object Finalizer {
    const val PART = "audio.aac.part"
    const val AUDIO = "audio.m4a"
    const val MARKS = "marks.jsonl"
    const val PEAKS = "peaks.bin"

    /**
     * Remuxes, verifies the result opens, then deletes the part file. The part is kept if anything
     * fails, so a bad finalize never loses audio. [pcmFrames] is the engine's exact count after a
     * normal Stop; recovery reads the duration from the file instead.
     * Returns null when the folder holds no audio at all.
     */
    fun finalize(folder: File, recovered: Boolean, pcmFrames: Long? = null, stopReason: String? = null): SavedRecording? {
        val part = File(folder, PART)
        val audio = File(folder, AUDIO)
        if (part.exists()) {
            val tmp = File(folder, "audio.m4a.tmp")
            if (!remux(part, tmp)) {
                tmp.delete()
                if (!audio.exists()) {
                    // Nothing was captured (stopped before the first frame): an empty folder is not a recording.
                    if (part.length() == 0L) folder.deleteRecursively()
                    return null
                }
            } else {
                check(durationUs(tmp) > 0) { "finalized file does not open" }
                tmp.renameTo(audio)
                part.delete()
            }
        }
        if (!audio.exists()) return null

        val old = Meta.read(folder) ?: return null
        val durationMs = pcmFrames?.let { Adts.framesToMs(it, old.sampleRate) } ?: (durationUs(audio) / 1000)
        val status = if (recovered) "recovered" else "saved"
        val meta = old.copy(status = if (old.status == "recording") status else old.status, durationMs = durationMs, stopReason = stopReason ?: old.stopReason)
        meta.write(folder)
        return saved(folder, meta)
    }

    fun saved(folder: File, meta: Meta) = SavedRecording(
        id = meta.id,
        folder = folder.absolutePath,
        createdAtMs = meta.createdAt,
        durationMs = meta.durationMs,
        marks = userMarks(Journal.read(File(folder, MARKS))),
        recovered = meta.status == "recovered",
        stopReason = meta.stopReason,
    )

    fun userMarks(entries: List<JournalEntry>) = entries.filter { it.kind == "user" }
        .mapIndexed { i, e -> MarkResult(e.id, e.positionMs, i + 1L) }

    /** Every folder with a part file that is not the live session: finalize it as recovered. */
    fun recoverAll(root: File, liveId: String?): List<SavedRecording> =
        root.listFiles().orEmpty()
            .filter { it.isDirectory && it.name != liveId && File(it, PART).exists() }
            .mapNotNull { runCatching { finalize(it, recovered = true) }.getOrNull() }

    private fun remux(part: File, out: File): Boolean {
        var muxer: MediaMuxer? = null
        var track = -1
        var index = 0L
        val info = MediaCodec.BufferInfo()
        try {
            part.inputStream().buffered().use { input ->
                Adts.readFrames(input) { f, payload ->
                    if (muxer == null) {
                        muxer = MediaMuxer(out.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                        val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, f.sampleRate, f.channels)
                        format.setByteBuffer("csd-0", ByteBuffer.wrap(Adts.audioSpecificConfig(f.sampleRate, f.channels)))
                        track = muxer!!.addTrack(format)
                        muxer!!.start()
                    }
                    info.set(0, payload.size, index * Adts.SAMPLES_PER_FRAME * 1_000_000L / f.sampleRate, MediaCodec.BUFFER_FLAG_KEY_FRAME)
                    muxer!!.writeSampleData(track, ByteBuffer.wrap(payload), info)
                    index++
                }
            }
            muxer?.stop()
        } finally {
            muxer?.release()
        }
        return index > 0
    }

    fun durationUs(file: File): Long {
        val ex = MediaExtractor()
        return try {
            ex.setDataSource(file.path)
            if (ex.trackCount != 1) 0 else ex.getTrackFormat(0).getLong(MediaFormat.KEY_DURATION)
        } catch (_: Exception) {
            0
        } finally {
            ex.release()
        }
    }
}
