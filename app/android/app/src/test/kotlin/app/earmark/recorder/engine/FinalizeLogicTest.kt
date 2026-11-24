package app.earmark.recorder.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files

/** The pure decisions behind finalize, recovery, low storage and clip export. */
class FinalizeLogicTest {
    private val mb = 1L shl 20

    private fun stream(vararg payloads: Int): ByteArray =
        payloads.fold(ByteArray(0)) { acc, n -> acc + Adts.header(n, 48_000, 1) + ByteArray(n) { it.toByte() } }

    private fun scan(bytes: ByteArray) = Adts.readFrames(ByteArrayInputStream(bytes)) { _, _ -> }

    @Test
    fun aWholeStreamIsReadToTheLastByte() {
        val full = stream(200, 310, 250)
        val s = scan(full)
        assertEquals(3L, s.frames)
        assertEquals(full.size.toLong(), s.bytes)
        assertTrue(Adts.readAll(s, full.size.toLong()))
    }

    @Test
    fun aTornLastFrameStillCountsAsReadAll() {
        val full = stream(200, 310, 250)
        val torn = full.copyOf(full.size - 100) // a crash mid-write of the last frame
        val s = scan(torn)
        assertEquals(2L, s.frames)
        assertEquals((7 + 200 + 7 + 310).toLong(), s.bytes)
        assertTrue(Adts.readAll(s, torn.size.toLong()))
        // A header cut off after 3 bytes is a torn tail too.
        val cutHeader = stream(200) + Adts.header(100, 48_000, 1).copyOf(3)
        assertTrue(Adts.readAll(scan(cutHeader), cutHeader.size.toLong()))
    }

    @Test
    fun damageMidFileStopsTheReadAndKeepsThePart() {
        val damaged = stream(200, 310, 250, 250, 250)
        damaged[7 + 200] = 0 // the second frame's sync word
        val s = scan(damaged)
        assertEquals(1L, s.frames)
        assertEquals(207L, s.bytes)
        assertFalse(Adts.readAll(s, damaged.size.toLong()))
    }

    @Test
    fun recordingStopsWhileFinalizeStillHasRoomForItsCopy() {
        assertFalse(Space.mustStop(free = 500 * mb, partBytes = 400 * mb))
        assertTrue(Space.mustStop(free = 440 * mb, partBytes = 400 * mb)) // 50 MB alone is not enough now
        assertTrue(Space.mustStop(free = 49 * mb, partBytes = 0))
        // From the last free-space check to Stop, 15 s of audio (~180 KB) more is written: still fits.
        for (part in listOf(0L, 10 * mb, 400 * mb, 4_000 * mb)) {
            val free = Space.STOP + part // the least free space that keeps recording
            assertTrue("part $part", Space.canRemux(free - mb, part + mb))
        }
    }

    @Test
    fun noRemuxWithoutRoomForTheCopy() {
        assertFalse(Space.canRemux(free = 100 * mb, partBytes = 90 * mb))
        assertTrue(Space.canRemux(free = 110 * mb, partBytes = 90 * mb))
        assertFalse(Space.canRemux(free = 0, partBytes = 0))
    }

    @Test
    fun aLostMetaIsRebuiltFromTheAudioAndWrittenAtomically() {
        val dir = Files.createTempDirectory("meta").toFile()
        try {
            assertNull(Meta.read(dir))
            File(dir, "meta.json").writeText("{\"id\":\"x\",\"crea") // torn by a power loss
            assertNull(Meta.read(dir))

            val m = Meta.rebuilt("abc", Adts.Format(44_100, 1), 1_234L, 96_000)
            assertEquals(Meta("abc", 1_234L, 44_100, 1, 96_000, "recovered"), m)
            m.write(dir)
            val final = m.copy(durationMs = 5_000, stopReason = "low_storage")
            final.write(dir) // replaces the file that is there
            assertEquals(final, Meta.read(dir))
            assertFalse(File(dir, "meta.json.tmp").exists())
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun marksPastTheRecoveredAudioAreClampedToItsEnd() {
        val entries = listOf(
            JournalEntry("a", 48_000, 48_000, 1, "app"), // 1 s
            JournalEntry("s", 96_000, 48_000, 2, "system", "system", "call"),
            JournalEntry("b", 480_000, 48_000, 3, "tile"), // 10 s, past a 4 s file
        )
        val marks = Finalizer.userMarks(entries, durationMs = 4_000)
        assertEquals(listOf(1_000L, 4_000L), marks.map { it.positionMs })
        assertEquals(listOf(1L, 2L), marks.map { it.index })
        assertEquals(listOf(1_000L, 10_000L), Finalizer.userMarks(entries).map { it.positionMs }) // 0 = unknown
    }

    @Test
    fun aMarkSyncedAfterStopClosedTheJournalIsStillDurable() {
        val f = File.createTempFile("marks", ".jsonl")
        try {
            val j = Journal(f)
            j.write(JournalEntry("a", 1, 48_000, 1, "tile"))
            j.close() // Stop wins the race: close syncs first
            j.sync() // the mark's own sync must not fail it
            assertEquals(listOf("a"), Journal.read(f).map { it.id })
        } finally {
            f.delete()
        }
    }

    @Test
    fun clipNamesAreSafeShortAndAlwaysM4a() {
        val dash = "—"
        assertEquals("Talk $dash Mark 1 (00-04 to 00-38).m4a", ClipExporter.clipName("Talk $dash Mark 1 (00-04 to 00-38).m4a"))
        assertEquals("Talk.m4a", ClipExporter.clipName("Talk"))
        assertEquals("a-b-c-d-e.m4a", ClipExporter.clipName("a/b:c\nd\\e"))
        assertEquals("clip.m4a", ClipExporter.clipName("  .M4A"))
        assertEquals("clip.m4a", ClipExporter.clipName(""))
        assertEquals("clip.m4a", ClipExporter.clipName("..."))
    }

    @Test
    fun clipNamesAreCutByUtf8BytesWithoutSplittingCharacters() {
        // A long title keeps its extension (take(120) used to cut it off).
        assertEquals("x".repeat(200) + ".m4a", ClipExporter.clipName("x".repeat(300) + ".m4a"))
        // CJK: 3 bytes each, so 66 fit in 200 bytes; the name stays far below the 255-byte limit.
        val kanji = "録"
        val cjk = ClipExporter.clipName(kanji.repeat(100) + ".m4a")
        assertEquals(kanji.repeat(66) + ".m4a", cjk)
        assertTrue(cjk.toByteArray(Charsets.UTF_8).size + ".tmp".length <= 255)
        // Emoji: a surrogate pair each (4 bytes); never cut in half.
        val note = "🎵"
        assertEquals(note.repeat(50) + ".m4a", ClipExporter.clipName(note.repeat(60)))
        // A character that does not fit whole is dropped, not split.
        assertEquals("y".repeat(199) + ".m4a", ClipExporter.clipName("y".repeat(199) + kanji))
        // A lone surrogate has no UTF-8 form.
        assertEquals("a-b.m4a", ClipExporter.clipName("a\uD83Cb"))
    }
}
