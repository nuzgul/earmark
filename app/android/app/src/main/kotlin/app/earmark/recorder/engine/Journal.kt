package app.earmark.recorder.engine

import org.json.JSONObject
import java.io.Closeable
import java.io.File
import java.io.FileOutputStream

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

    fun append(entry: JournalEntry) {
        out.write((entry.toJson() + "\n").toByteArray())
        out.fd.sync()
    }

    override fun close() = out.close()

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

/** meta.json: what Phase 2 imports into the library. Written atomically (temp + rename). */
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
        tmp.writeText(
            JSONObject().put("id", id).put("created_at", createdAt).put("sample_rate", sampleRate)
                .put("channels", channels).put("bitrate", bitrate).put("status", status)
                .put("duration_ms", durationMs).put("stop_reason", stopReason ?: JSONObject.NULL).toString(),
        )
        tmp.renameTo(File(folder, "meta.json"))
    }

    companion object {
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
