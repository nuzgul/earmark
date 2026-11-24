package app.earmark.recorder.engine

import android.system.Os
import android.system.OsConstants
import org.json.JSONObject
import java.io.Closeable
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** Atomic rename over [target]; throws instead of failing quietly like File.renameTo. */
fun File.replace(target: File) {
    Files.move(toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE)
}

/** fsyncs a directory so a rename in it survives power loss. Best effort (a no-op on the JVM in tests). */
fun syncDir(dir: File) {
    runCatching {
        val fd = Os.open(dir.path, OsConstants.O_RDONLY, 0)
        try {
            Os.fsync(fd)
        } finally {
            Os.close(fd)
        }
    }
}

/** One line of marks.jsonl. kind "system" marks an interruption (call) and is not a user mark. */
data class JournalEntry(
    val id: String,
    val posFrames: Long,
    val sampleRate: Int,
    val createdAt: Long,
    val source: String,
    val kind: String = "user",
    val note: String? = null,
) {
    val positionMs get() = Adts.framesToMs(posFrames, sampleRate)

    fun toJson(): String = JSONObject()
        .put("id", id).put("pos_frames", posFrames).put("sample_rate", sampleRate)
        .put("created_at", createdAt).put("source", source).put("kind", kind)
        .apply { if (note != null) put("note", note) }
        .toString()
}

/** Append-only mark journal. Every line is fsynced before the mark is confirmed. */
class Journal(file: File) : Closeable {
    private val out = FileOutputStream(file, true)
    @Volatile private var closed = false

    fun append(entry: JournalEntry) {
        write(entry)
        sync()
    }

    /** Unsynced append: the caller orders lines under its lock and calls [sync] after releasing it. */
    fun write(entry: JournalEntry) = out.write((entry.toJson() + "\n").toByteArray())

    /** Makes every written line durable. A no-op once closed, because [close] syncs first. */
    fun sync() {
        try {
            out.fd.sync()
        } catch (e: IOException) {
            if (!closed) throw e
        }
    }

    override fun close() {
        runCatching { out.fd.sync() }
        closed = true
        out.close()
    }

    companion object {
        /** Reads every whole line; a line cut off by a crash is skipped. */
        fun read(file: File): List<JournalEntry> {
            if (!file.exists()) return emptyList()
            return file.readLines().mapNotNull { line ->
                runCatching {
                    val o = JSONObject(line)
                    JournalEntry(
                        o.getString("id"), o.getLong("pos_frames"), o.getInt("sample_rate"),
                        o.getLong("created_at"), o.getString("source"), o.optString("kind", "user"),
                        if (o.has("note")) o.getString("note") else null,
                    )
                }.getOrNull()
            }
        }
    }
}

/** meta.json: what Phase 2 imports into the library. Written atomically (temp + fsync + rename). */
data class Meta(
    val id: String,
    val createdAt: Long,
    val sampleRate: Int,
    val channels: Int,
    val bitrate: Int,
    val status: String, // recording | saved | recovered
    val durationMs: Long = 0,
    val stopReason: String? = null,
) {
    fun write(folder: File) {
        val tmp = File(folder, "meta.json.tmp")
        FileOutputStream(tmp).use {
            it.write(
                JSONObject().put("id", id).put("created_at", createdAt).put("sample_rate", sampleRate)
                    .put("channels", channels).put("bitrate", bitrate).put("status", status)
                    .put("duration_ms", durationMs).put("stop_reason", stopReason ?: JSONObject.NULL).toString()
                    .toByteArray(),
            )
            it.fd.sync() // the finalizer deletes the part only after this file is durable
        }
        tmp.replace(File(folder, "meta.json"))
        syncDir(folder)
    }

    companion object {
        /**
         * meta.json was lost or torn (a crash or power loss mid-write): rebuild what the audio itself
         * tells. [createdAt] is the folder's time, the best trace of the start that is left.
         */
        fun rebuilt(id: String, format: Adts.Format, createdAt: Long, bitrate: Int) =
            Meta(id, createdAt, format.sampleRate, format.channels, bitrate, "recovered")

        fun read(folder: File): Meta? = runCatching {
            val o = JSONObject(File(folder, "meta.json").readText())
            Meta(
                o.getString("id"), o.getLong("created_at"), o.getInt("sample_rate"), o.getInt("channels"),
                o.getInt("bitrate"), o.getString("status"), o.optLong("duration_ms"),
                if (o.isNull("stop_reason")) null else o.getString("stop_reason"),
            )
        }.getOrNull()
    }
}
