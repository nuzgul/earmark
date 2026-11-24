package app.earmark.recorder.engine

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.StatFs
import android.util.Log
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer

/** Free-space rules. Finalizing writes a second copy of the part, so its size is reserved too. */
object Space {
    const val MIN_START = 100L shl 20
    const val STOP = 50L shl 20
    const val MARGIN = 16L shl 20 // the m4a's index and meta.json, with room to spare

    /** Stop recording while finalize still has room for the m4a copy. */
    fun mustStop(free: Long, partBytes: Long) = free < STOP + partBytes

    /** Remux only when the copy fits; otherwise the part waits for a later recovery. */
    fun canRemux(free: Long, partBytes: Long) = free > partBytes + MARGIN
}

/** Turns a session folder's crash-safe ADTS stream into the final audio.m4a (no re-encode). */
object Finalizer {
    private const val TAG = "Earmark"
    const val PART = "audio.aac.part"
    const val AUDIO = "audio.m4a"
    const val MARKS = "marks.jsonl"
    const val PEAKS = "peaks.bin"
    /** A part that damage cut short keeps its bytes under this name; recovery no longer retries it. */
    const val UNREAD = "audio.aac.unread"
    private const val TMP = "audio.m4a.tmp"

    /**
     * Remuxes, verifies the result opens, writes the final meta.json (fsynced), then deletes the
     * part file. The part is kept if anything fails, or if damage stopped the remux early, so a bad
     * finalize never loses audio. [pcmFrames] is the engine's exact count after a normal Stop;
     * recovery reads the duration from the file instead.
     * Returns null when the folder holds no audio at all, or there is no room to finalize yet.
     */
    fun finalize(folder: File, recovered: Boolean, pcmFrames: Long? = null, stopReason: String? = null): SavedRecording? {
        val part = File(folder, PART)
        val audio = File(folder, AUDIO)
        val tmp = File(folder, TMP)
        val folderTime = folder.lastModified() // before this run touches the folder
        val known = Meta.read(folder)
        var scan: Adts.Scan? = null
        var partBytes = 0L
        var fileUs = 0L
        if (part.exists()) {
            tmp.delete() // left behind by a kill mid-remux
            partBytes = part.length()
            val free = StatFs(folder.path).availableBytes
            if (!Space.canRemux(free, partBytes)) {
                Log.w(TAG, "${folder.name}: $free bytes free for a $partBytes-byte part; kept for a later recovery")
                return null
            }
            try {
                val r = remux(part, tmp)
                if (r.frames > 0) {
                    fileUs = durationUs(tmp)
                    check(fileUs > 0) { "finalized file does not open" }
                    tmp.replace(audio)
                    scan = r
                } else if (!audio.exists()) {
                    // Nothing was captured (stopped before the first frame): an empty folder is not a recording.
                    if (partBytes == 0L) folder.deleteRecursively()
                    return null
                }
            } finally {
                tmp.delete() // no-op once renamed; never leave a second copy filling the disk
            }
        }
        if (!audio.exists()) return null

        val old = known ?: scan?.format?.let {
            Log.w(TAG, "${folder.name}: meta.json unreadable, rebuilt from the audio")
            Meta.rebuilt(folder.name, it, folderTime, RecorderEngine.BITRATE)
        } ?: return null
        val whole = scan == null || Adts.readAll(scan, partBytes)
        if (fileUs == 0L) fileUs = durationUs(audio)
        // The engine's exact count, unless damage cut the file shorter than what was captured.
        val durationMs = pcmFrames?.takeIf { whole }?.let { Adts.framesToMs(it, old.sampleRate) } ?: (fileUs / 1000)
        val status = if (recovered) "recovered" else "saved"
        val meta = old.copy(status = if (old.status == "recording") status else old.status, durationMs = durationMs, stopReason = stopReason ?: old.stopReason)
        meta.write(folder) // durable before the part goes
        if (scan != null) {
            if (whole) {
                part.delete()
            } else {
                Log.w(TAG, "${folder.name}: damage stopped the remux at byte ${scan.bytes} of $partBytes; part kept as $UNREAD")
                runCatching { part.replace(File(folder, UNREAD)) }.onFailure { Log.w(TAG, "keeping the part as is", it) }
            }
        }
        return saved(folder, meta)
    }

    fun saved(folder: File, meta: Meta) = SavedRecording(
        id = meta.id,
        folder = folder.absolutePath,
        createdAtMs = meta.createdAt,
        durationMs = meta.durationMs,
        marks = userMarks(Journal.read(File(folder, MARKS)), meta.durationMs),
        recovered = meta.status == "recovered",
        stopReason = meta.stopReason,
    )

    /**
     * Marks are fsynced at once but audio only every few seconds, so after a power loss a mark can
     * point past the recovered audio: clamp it to [durationMs] (0 = unknown). The journal is untouched.
     */
    fun userMarks(entries: List<JournalEntry>, durationMs: Long = 0) = entries.filter { it.kind == "user" }
        .mapIndexed { i, e ->
            MarkResult(e.id, if (durationMs > 0) minOf(e.positionMs, durationMs) else e.positionMs, i + 1L)
        }

    /** Every folder with a part file that is not the live session. Cheap: callers take it under the engine lock. */
    fun pending(root: File, liveId: String?): List<File> =
        root.listFiles().orEmpty().filter { it.isDirectory && it.name != liveId && File(it, PART).exists() }

    /** Finalizes [folders] as recovered; one that fails stays as it is for the next launch. */
    fun recoverAll(folders: List<File>): List<SavedRecording> = folders.mapNotNull { f ->
        runCatching { finalize(f, recovered = true) }.onFailure { Log.e(TAG, "recover ${f.name} failed", it) }.getOrNull()
    }

    /** Copies the part's whole frames into [out] (no re-encode) and fsyncs it once at the end. */
    private fun remux(part: File, out: File): Adts.Scan {
        var muxer: MediaMuxer? = null
        var track = -1
        var index = 0L
        val info = MediaCodec.BufferInfo()
        // MediaMuxer(path) opens the file O_SYNC (a flush per write); one fsync before the rename suffices.
        RandomAccessFile(out, "rw").use { file ->
            file.setLength(0)
            val scan = try {
                val r = part.inputStream().buffered().use { input ->
                    Adts.readFrames(input) { f, payload ->
                        val m = muxer ?: MediaMuxer(file.fd, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4).also {
                            muxer = it
                            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, f.sampleRate, f.channels)
                            format.setByteBuffer("csd-0", ByteBuffer.wrap(Adts.audioSpecificConfig(f.sampleRate, f.channels)))
                            track = it.addTrack(format)
                            it.start()
                        }
                        info.set(0, payload.size, index * Adts.SAMPLES_PER_FRAME * 1_000_000L / f.sampleRate, MediaCodec.BUFFER_FLAG_KEY_FRAME)
                        m.writeSampleData(track, ByteBuffer.wrap(payload), info)
                        index++
                    }
                }
                muxer?.stop()
                r
            } finally {
                muxer?.release()
            }
            file.fd.sync()
            return scan
        }
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
