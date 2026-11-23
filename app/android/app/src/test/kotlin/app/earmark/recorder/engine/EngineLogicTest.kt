package app.earmark.recorder.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.File

class EngineLogicTest {
    private fun stream(vararg payloads: Int): ByteArray =
        payloads.fold(ByteArray(0)) { acc, n -> acc + Adts.header(n, 48_000, 1) + ByteArray(n) { it.toByte() } }

    @Test
    fun framesToMsExcludesNothingButFrames() {
        assertEquals(10_000, Adts.framesToMs(480_000, 48_000))
        assertEquals(20_000, Adts.framesToMs(882_000, 44_100))
        assertEquals(21, Adts.framesToMs(1024, 48_000))
    }

    @Test
    fun adtsRoundTripReadsEveryFrameAndTheFormat() {
        val sizes = mutableListOf<Int>()
        val format = Adts.readFrames(ByteArrayInputStream(stream(200, 310, 5))) { _, p -> sizes += p.size }
        assertEquals(Adts.Format(48_000, 1), format)
        assertEquals(listOf(200, 310, 5), sizes)
    }

    @Test
    fun adtsStopsAtATruncatedLastFrame() {
        val full = stream(200, 310)
        val cut = full.copyOf(full.size - 40) // a crash mid-write
        var count = 0
        Adts.readFrames(ByteArrayInputStream(cut)) { _, _ -> count++ }
        assertEquals(1, count)
        assertNull(Adts.readFrames(ByteArrayInputStream(ByteArray(3))) { _, _ -> })
    }

    @Test
    fun audioSpecificConfigIsAacLc48kMono() {
        // object type 2, rate index 3, 1 channel -> 0x11 0x88
        assertEquals(listOf(0x11, 0x88), Adts.audioSpecificConfig(48_000, 1).map { it.toInt() and 0xFF })
    }

    @Test
    fun journalSkipsALineCutOffByACrash() {
        val f = File.createTempFile("marks", ".jsonl")
        try {
            Journal(f).use {
                it.append(JournalEntry("a", 480_000, 48_000, 1, "app"))
                it.append(JournalEntry("s", 500_000, 48_000, 2, "system", "system", "call"))
                it.append(JournalEntry("b", 960_000, 48_000, 3, "notification"))
            }
            f.appendText("{\"id\":\"c\",\"pos_fr") // torn write
            val entries = Journal.read(f)
            assertEquals(listOf("a", "s", "b"), entries.map { it.id })
            val marks = Finalizer.userMarks(entries)
            assertEquals(listOf(10_000L, 20_000L), marks.map { it.positionMs })
            assertEquals(listOf(1L, 2L), marks.map { it.index })
        } finally {
            f.delete()
        }
    }
}
