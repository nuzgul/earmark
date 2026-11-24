package app.earmark.recorder.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files
import kotlin.random.Random

/**
 * Property tests: thousands of random inputs against the readers that recovery depends on.
 * Seeds are fixed so a failure reproduces; the failing seed is in the message.
 */
class PropertyTest {
    private fun scan(bytes: ByteArray) = Adts.readFrames(ByteArrayInputStream(bytes)) { _, _ -> }

    private fun stream(rnd: Random, frames: Int): Pair<ByteArray, IntArray> {
        val sizes = IntArray(frames) { rnd.nextInt(1, 760) }
        val out = java.io.ByteArrayOutputStream()
        for (n in sizes) {
            out.write(Adts.header(n, 48_000, 1))
            out.write(ByteArray(n) { rnd.nextInt().toByte() })
        }
        return out.toByteArray() to sizes
    }

    @Test
    fun randomBytesNeverCrashTheReaderAndNeverReadPastTheEnd() {
        repeat(5_000) { seed ->
            val rnd = Random(seed)
            val bytes = rnd.nextBytes(rnd.nextInt(0, 4_000))
            val s = scan(bytes)
            assertTrue("seed $seed", s.bytes in 0..bytes.size.toLong())
            assertTrue("seed $seed", s.frames >= 0 && s.frames * Adts.HEADER <= s.bytes)
        }
    }

    @Test
    fun aCutStreamKeepsExactlyTheWholeFramesBeforeTheCut() {
        repeat(2_000) { seed ->
            val rnd = Random(seed)
            val (full, sizes) = stream(rnd, rnd.nextInt(1, 40))
            val cut = rnd.nextInt(0, full.size + 1)
            var whole = 0
            var end = 0L
            for (n in sizes) {
                if (end + Adts.HEADER + n > cut) break
                end += Adts.HEADER + n
                whole++
            }
            val s = scan(full.copyOf(cut))
            assertEquals("seed $seed frames", whole.toLong(), s.frames)
            assertEquals("seed $seed bytes", end, s.bytes)
            // A torn tail shorter than one frame still counts as read to the end.
            assertTrue("seed $seed readAll", Adts.readAll(s, cut.toLong()))
        }
    }

    @Test
    fun damageMidStreamStopsTheScanAndIsReportedAsUnread() {
        repeat(1_000) { seed ->
            val rnd = Random(seed)
            val (full, _) = stream(rnd, 60)
            val at = rnd.nextInt(full.size / 4, full.size / 2)
            val damaged = full.copyOf().also { b -> for (i in at until minOf(at + 2048, b.size)) b[i] = 0 }
            val s = scan(damaged)
            assertTrue("seed $seed", s.bytes <= at + 2048)
            assertFalse("seed $seed: more than a frame left unread must keep the part", Adts.readAll(s, damaged.size.toLong()))
        }
    }

    @Test
    fun theJournalKeepsEveryWholeLineAndSkipsGarbage() {
        val dir = Files.createTempDirectory("journal").toFile()
        repeat(500) { seed ->
            val rnd = Random(seed)
            val good = (0 until rnd.nextInt(0, 20)).map {
                JournalEntry("m$seed-$it", rnd.nextLong(0, 1L shl 40), 48_000, rnd.nextLong(0, Long.MAX_VALUE), "app")
            }
            val lines = good.map { it.toJson() }.toMutableList()
            repeat(rnd.nextInt(0, 6)) {
                val junk = String(CharArray(rnd.nextInt(0, 80)) { (rnd.nextInt(32, 0x2FFF)).toChar() })
                lines.add(rnd.nextInt(0, lines.size + 1), junk.replace("\n", " "))
            }
            val torn = if (rnd.nextBoolean() && good.isNotEmpty()) good.last().toJson().take(rnd.nextInt(1, 20)) else ""
            val f = File(dir, "marks-$seed.jsonl")
            f.writeText(lines.joinToString("\n", postfix = "\n") + torn)
            val read = Journal.read(f)
            assertEquals("seed $seed", good.map { it.id }, read.map { it.id }.filter { id -> good.any { it.id == id } })
            assertTrue("seed $seed: no invented entries", read.all { e -> good.any { it.id == e.id } })
        }
        dir.deleteRecursively()
    }

    @Test
    fun clipNamesAreAlwaysSafeShortAndEndInM4a() {
        val reserved = "\\/:*?\"<>|"
        repeat(5_000) { seed ->
            val rnd = Random(seed)
            val title = buildString {
                repeat(rnd.nextInt(0, 300)) {
                    append(
                        when (rnd.nextInt(5)) {
                            0 -> reserved[rnd.nextInt(reserved.length)]
                            1 -> rnd.nextInt(0x4E00, 0x9FFF).toChar() // CJK
                            2 -> rnd.nextInt(0xD800, 0xE000).toChar() // possibly lone surrogates
                            3 -> rnd.nextInt(0, 32).toChar() // control
                            else -> rnd.nextInt(32, 127).toChar()
                        },
                    )
                }
            }
            val name = ClipExporter.clipName(title)
            assertTrue("seed $seed: '$name'", name.endsWith(".m4a"))
            assertTrue("seed $seed bytes", name.toByteArray(Charsets.UTF_8).size <= 204)
            assertTrue("seed $seed reserved", name.dropLast(4).none { it in reserved || it.code < 32 })
            assertFalse("seed $seed surrogate", name.indices.any { i ->
                val c = name[i]
                (c.isHighSurrogate() && (i + 1 >= name.length || !name[i + 1].isLowSurrogate())) ||
                    (c.isLowSurrogate() && (i == 0 || !name[i - 1].isHighSurrogate()))
            })
        }
    }
}
