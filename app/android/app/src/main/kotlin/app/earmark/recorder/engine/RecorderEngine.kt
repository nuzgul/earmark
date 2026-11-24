package app.earmark.recorder.engine

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioManager
import android.media.AudioRecordingConfiguration
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.os.StatFs
import android.os.SystemClock
import android.util.Log
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteOrder
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors
import java.util.concurrent.Future
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlin.math.log10

/**
 * The recording session, process-wide. It outlives the Flutter UI (the foreground service keeps
 * the process alive), so the notification and the Quick Settings tile can mark with no UI running.
 *
 * Timing: [Session.frames] counts PCM frames handed to the encoder. A mark stores that count, so
 * its position is exact to one read (~21 ms) and paused time is excluded by construction.
 */
@SuppressLint("StaticFieldLeak") // holds the application context only
object RecorderEngine {
    private const val TAG = "Earmark"
    const val BITRATE = 96_000
    private const val CHUNK = 1024 // frames per read, ~21 ms at 48 kHz
    private const val HEARTBEAT_MS = 250L
    private const val STALL_MS = 1000L
    private const val SYNC_MS = 5_000L
    private const val WAKE_MS = 24 * 3600 * 1000L // only bounds a leak; stop() releases it

    interface Listener {
        fun onSnapshot(s: EngineSnapshot) {}
        fun onMark(m: MarkResult) {}
        fun onSaved(r: SavedRecording) {}
    }

    private lateinit var app: Context
    private val main = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArraySet<Listener>()
    private val worker = Executors.newSingleThreadExecutor()
    /** fsyncs the part off the capture thread: a slow flush must never hold up AudioRecord reads. */
    private val syncer = Executors.newSingleThreadExecutor()
    /** Tile and notification marks: in tap order, with their fsync off the main thread. */
    private val marker = Executors.newSingleThreadExecutor()
    /** Serializes recover() calls without holding the engine lock that start() needs. */
    private val recovering = Any()

    @Volatile private var session: Session? = null

    /** Debug builds only: record a clock-paced test tone instead of the microphone (integration tests). */
    @Volatile var testTone = false

    fun init(context: Context) {
        if (::app.isInitialized) return
        app = context.applicationContext
        worker.execute { runCatching { measureFree() } } // the first snapshot already knows the space
    }

    fun addListener(l: Listener) = listeners.add(l)
    fun removeListener(l: Listener) = listeners.remove(l)

    val isActive get() = session != null
    /** The live session's id, null when idle. */
    val liveId: String? get() = session?.id
    /** Created once (mkdirs on every access was a main-thread disk call, StrictMode). */
    val root: File by lazy { File(app.filesDir, "recordings").apply { mkdirs() } }

    // Free space for snapshots (main thread, 4 per second) comes from a cache refreshed off the
    // main thread; start() and the capture thread's 15 s check measure it fresh.
    @Volatile private var freeCache = 0L
    @Volatile private var freeAt = 0L

    private fun measureFree(): Long = StatFs(root.path).availableBytes.also {
        freeCache = it
        freeAt = SystemClock.elapsedRealtime()
    }

    private fun freeBytes(fresh: Boolean = false): Long {
        if (fresh) return measureFree()
        if (SystemClock.elapsedRealtime() - freeAt > 5_000) {
            freeAt = SystemClock.elapsedRealtime() // one refresh in flight at a time
            worker.execute { runCatching { measureFree() } }
        }
        return freeCache
    }

    private class Session(
        val id: String, val folder: File, val rate: Int, @Volatile var source: PcmSource, val codec: MediaCodec,
        val wake: PowerManager.WakeLock,
    ) {
        val part = FileOutputStream(File(folder, Finalizer.PART))
        val journal = Journal(File(folder, Finalizer.MARKS))
        val peaks = BufferedOutputStream(FileOutputStream(File(folder, Finalizer.PEAKS)))
        @Volatile var state = SessionState.STARTING
        @Volatile var interruption: String? = null
        @Volatile var frames = 0L
        @Volatile var wantPaused = false
        @Volatile var silenced = false
        @Volatile var stopRequested = false
        @Volatile var level = 0.0
        @Volatile var markCount = 0L
        @Volatile var lastAdvanceAt = 0L
        @Volatile var syncing: Future<*>? = null
        var stopReason: String? = null
        var queued = 0L
        var lastFrames = -1L
        val done = CompletableFuture<SavedRecording?>()
        lateinit var thread: Thread

        fun close() {
            runCatching { syncing?.get() } // an in-flight fsync finishes before its fd closes
            runCatching { source.release() }
            runCatching { codec.stop() }
            runCatching { codec.release() }
            runCatching { part.fd.sync() }
            part.close()
            journal.close()
            peaks.close()
        }
    }

    fun snapshot(resetLevel: Boolean = false): EngineSnapshot {
        val s = session ?: return EngineSnapshot(SessionState.IDLE, null, 0, 0.0, 0, null, freeBytes())
        val level = s.level
        if (resetLevel) s.level = 0.0
        return EngineSnapshot(s.state, s.id, Adts.framesToMs(s.frames, s.rate), level, s.markCount, s.interruption, freeBytes())
    }

    /**
     * Starts capture. The caller has the microphone permission. State stays STARTING until frames
     * arrive. Blocking (opens the mic and the encoder, writes files): call off the main thread.
     */
    @Synchronized
    fun start(): EngineSnapshot {
        if (session != null) return snapshot()
        if (freeBytes(fresh = true) < Space.MIN_START) {
            throw FlutterError("low_storage", "Not enough free space to record. Free up at least 100 MB and try again.")
        }
        val busy = FlutterError("mic_busy", "The microphone isn't available right now. Close other apps that use it and try again.")
        val tone = testTone
        val rate = if (tone) 48_000 else intArrayOf(48_000, 44_100).firstOrNull(MicSource::supports) ?: throw busy
        val source = if (tone) ToneSource(rate) else MicSource.open(rate) ?: throw busy
        val codec = try {
            MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC).apply {
                val f = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, rate, 1)
                f.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                f.setInteger(MediaFormat.KEY_BIT_RATE, BITRATE)
                f.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, CHUNK * 2 * 2)
                configure(f, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                start()
            }
        } catch (e: Exception) {
            source.release()
            throw FlutterError("encoder", "This phone's audio encoder could not start.", e.message)
        }
        val id = UUID.randomUUID().toString()
        val folder = File(root, id)
        var started: Session? = null
        try {
            folder.mkdirs()
            Meta(id, System.currentTimeMillis(), rate, 1, BITRATE, "recording").write(folder)
            val wake = app.getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Earmark:recording")
            wake.setReferenceCounted(false)
            val s = Session(id, folder, rate, source, codec, wake)
            started = s
            wake.acquire(WAKE_MS) // capture goes on with the screen off; released in stop()
            session = s
            audioManager().registerAudioRecordingCallback(recordingCallback, main)
            s.thread = thread(name = "earmark-capture") { capture(s) }
        } catch (e: Exception) {
            // Nothing records: hand back the mic and the encoder so the next Record tap can have them.
            session = null
            runCatching { audioManager().unregisterAudioRecordingCallback(recordingCallback) }
            val s = started
            if (s != null) {
                runCatching { s.wake.release() }
                runCatching { s.close() }
            } else {
                runCatching { source.release() }
                runCatching { codec.stop() }
                runCatching { codec.release() }
            }
            folder.deleteRecursively() // holds no audio and no marks yet
            throw FlutterError("storage", "Recording couldn't start: the recording file could not be created.", e.message)
        }
        main.removeCallbacks(tick)
        main.post(tick)
        return snapshot()
    }

    fun pause(): EngineSnapshot {
        session?.let { s ->
            synchronized(s) {
                if (!s.stopRequested && s.state != SessionState.PAUSED) {
                    s.wantPaused = true
                    s.state = SessionState.PAUSED
                    s.interruption = null
                }
            }
        }
        return snapshot().also(::emit)
    }

    fun resume(): EngineSnapshot {
        session?.let { s ->
            synchronized(s) {
                if (!s.stopRequested && s.state == SessionState.PAUSED) {
                    s.wantPaused = false
                    if (s.silenced) setState(s, SessionState.INTERRUPTED, "call") else setState(s, SessionState.RECORDING, null)
                }
            }
        }
        return snapshot().also(::emit)
    }

    /** Records a mark at the current frame and fsyncs it before returning. */
    fun mark(source: String): MarkResult {
        val s = session ?: throw FlutterError("not_recording", "Nothing is recording.")
        val result = synchronized(s) {
            if (s.stopRequested) throw FlutterError("not_recording", "The recording is being saved.")
            val e = JournalEntry(UUID.randomUUID().toString(), s.frames, s.rate, System.currentTimeMillis(), source)
            s.journal.write(e) // under the lock: lines stay in frame order
            s.markCount++
            MarkResult(e.id, e.positionMs, s.markCount)
        }
        // fsync outside the lock, so Pause and the capture thread never wait on the disk. Stop syncs
        // the journal before closing it, so a mark racing Stop is durable either way.
        s.journal.sync()
        main.post { listeners.forEach { it.onMark(result) } }
        emit(snapshot())
        return result
    }

    /** Tile and notification: marks in tap order, the fsync off the main thread. [done] runs on the main thread. */
    fun markInBackground(source: String, done: (MarkResult) -> Unit = {}) {
        marker.execute {
            runCatching { mark(source) }
                .onSuccess { r -> main.post { done(r) } }
                .onFailure { Log.w(TAG, "$source mark failed", it) }
        }
    }

    /**
     * Stops, finalizes and returns the saved recording. Blocking: call off the main thread.
     * A second caller (app and notification at once) waits for the first one's result.
     */
    fun stop(reason: String? = null): SavedRecording? {
        val s = session ?: return null
        val first = synchronized(s) {
            if (s.stopRequested) false else {
                s.stopRequested = true
                s.stopReason = reason
                s.state = SessionState.FINALIZING
                true
            }
        }
        if (!first) return s.done.get()
        emit(snapshot())
        var saved: SavedRecording? = null
        try {
            s.thread.join()
            s.close()
            saved = Finalizer.finalize(s.folder, recovered = false, pcmFrames = s.frames, stopReason = s.stopReason)
        } catch (e: Exception) {
            // The part file stays on disk; recover() finishes it on the next launch.
            Log.e(TAG, "finalize failed", e)
        } finally {
            // Synchronously: a posted unregister could run after the next start() registered again.
            runCatching { audioManager().unregisterAudioRecordingCallback(recordingCallback) }
            runCatching { s.wake.release() }
            session = null
            s.done.complete(saved)
            emit(snapshot())
            saved?.let { r -> main.post { listeners.forEach { it.onSaved(r) } } }
        }
        return saved
    }

    /**
     * Finalizes sessions a crash left behind. Blocking: call off the main thread. The engine lock is
     * held only to list the folders; a long remux under it would block start() on the main thread.
     */
    fun recover(): List<SavedRecording> = synchronized(recovering) {
        val folders = synchronized(this) { Finalizer.pending(root, session?.id) }
        Finalizer.recoverAll(folders)
    }

    private fun emit(s: EngineSnapshot) {
        main.post { listeners.forEach { it.onSnapshot(s) } }
    }

    private fun setState(s: Session, state: SessionState, why: String?) {
        if (state == SessionState.RECORDING) s.lastAdvanceAt = SystemClock.elapsedRealtime()
        s.state = state
        s.interruption = why
        emit(snapshot())
    }

    /** Heartbeat; also the stall watchdog: "Recording" is never shown while frames stand still. */
    private val tick = object : Runnable {
        override fun run() {
            val s = session ?: return
            val now = SystemClock.elapsedRealtime()
            if (s.frames != s.lastFrames) {
                s.lastFrames = s.frames
                s.lastAdvanceAt = now
            } else if (s.state == SessionState.RECORDING && now - s.lastAdvanceAt > STALL_MS) {
                synchronized(s) {
                    // Re-checked under the lock: Pause or Stop may have changed the state meanwhile.
                    if (s.state == SessionState.RECORDING && !s.stopRequested) {
                        s.state = SessionState.INTERRUPTED
                        s.interruption = "mic_lost"
                    }
                }
            }
            emit(snapshot(resetLevel = true))
            main.postDelayed(this, HEARTBEAT_MS)
        }
    }

    /** Android 10+ silences a recorder while a call (or another priority app) holds the mic. */
    private val recordingCallback = object : AudioManager.AudioRecordingCallback() {
        override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>) {
            val s = session ?: return
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
            if (s.source.sessionId == 0) return
            val mine = configs.firstOrNull { it.clientAudioSessionId == s.source.sessionId } ?: return
            if (mine.isClientSilenced == s.silenced) return
            synchronized(s) {
                if (s.stopRequested) return
                s.silenced = mine.isClientSilenced
                if (s.silenced) {
                    // A full disk must not crash the app from a system callback; the interruption still shows.
                    runCatching {
                        s.journal.append(JournalEntry(UUID.randomUUID().toString(), s.frames, s.rate, System.currentTimeMillis(), "system", "system", "call"))
                    }.onFailure { Log.w(TAG, "call mark not saved", it) }
                    if (s.state == SessionState.RECORDING || s.state == SessionState.STARTING) setState(s, SessionState.INTERRUPTED, "call")
                } else if (s.state == SessionState.INTERRUPTED && s.interruption == "call") {
                    setState(s, SessionState.RECORDING, null)
                }
            }
        }
    }

    private fun capture(s: Session) {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
        val buf = ShortArray(CHUNK)
        val info = MediaCodec.BufferInfo()
        val peakEvery = s.rate / 20 // one peaks.bin byte per 50 ms
        var peak = 0
        var peakFrames = 0
        var lastSync = SystemClock.elapsedRealtime()
        var lastStorage = lastSync
        try {
            if (!s.source.start()) micLost(s)
            while (!s.stopRequested) {
                // The mic keeps running while paused and those samples are dropped: Resume is then
                // instant (no clipped first word) and never re-opens the mic from the background.
                val n = s.source.read(buf, CHUNK)
                if (n < 0) { micLost(s); continue }
                if (n == 0 || s.wantPaused || s.silenced || s.stopRequested) continue

                encode(s, buf, n, info)
                var chunkPeak = 0
                for (i in 0 until n) {
                    val v = abs(buf[i].toInt())
                    if (v > chunkPeak) chunkPeak = v
                    if (v > peak) peak = v
                    if (++peakFrames == peakEvery) {
                        s.peaks.write(peak * 255 / 32768)
                        peak = 0
                        peakFrames = 0
                    }
                }
                s.frames += n // single writer: this thread
                val db = if (chunkPeak == 0) -90.0 else 20 * log10(chunkPeak / 32768.0)
                s.level = maxOf(s.level, ((db + 60) / 60).coerceIn(0.0, 1.0))
                if (waitingForFrames(s)) toRecording(s)

                val now = SystemClock.elapsedRealtime()
                if (now - lastSync > SYNC_MS) {
                    lastSync = now
                    s.peaks.flush() // a recovered recording keeps its waveform too
                    // The fsync runs on its own thread: on a busy disk it can outlast AudioRecord's
                    // buffer, and this thread must keep reading meanwhile. One in flight at a time.
                    if (s.syncing?.isDone != false) {
                        s.syncing = syncer.submit { runCatching { s.part.fd.sync() }.onFailure { Log.w(TAG, "part fsync failed", it) } }
                    }
                }
                if (now - lastStorage > 15_000) {
                    lastStorage = now
                    // Stop while finalize still has room for its copy of the part.
                    if (Space.mustStop(freeBytes(fresh = true), File(s.folder, Finalizer.PART).length())) worker.execute { stop("low_storage") }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "capture failed", e)
            worker.execute { stop("error") } // keep what was captured
        } finally {
            runCatching { endStream(s, info) }
            runCatching { s.peaks.flush() }
        }
    }

    private fun waitingForFrames(s: Session) =
        s.state == SessionState.STARTING || (s.state == SessionState.INTERRUPTED && s.interruption == "mic_lost")

    /** Frames arrive: show Recording, unless Pause, a call or Stop got in first (checked under the lock). */
    private fun toRecording(s: Session) = synchronized(s) {
        if (waitingForFrames(s) && !s.stopRequested && !s.wantPaused && !s.silenced) setState(s, SessionState.RECORDING, null)
    }

    private fun micLost(s: Session) {
        synchronized(s) {
            if (!s.stopRequested && !s.wantPaused && s.state != SessionState.INTERRUPTED) setState(s, SessionState.INTERRUPTED, "mic_lost")
        }
        runCatching { s.source.release() }
        while (!s.stopRequested) {
            SystemClock.sleep(500)
            val again = MicSource.open(s.rate) ?: continue
            if (again.start()) {
                s.source = again
                return
            }
            runCatching { again.release() } // a failed start still holds an AudioRecord
        }
    }

    private fun encode(s: Session, buf: ShortArray, n: Int, info: MediaCodec.BufferInfo) {
        var off = 0
        while (off < n) {
            val idx = s.codec.dequeueInputBuffer(10_000)
            if (idx < 0) { drain(s, info, false); continue }
            val ib = s.codec.getInputBuffer(idx)!!
            ib.clear()
            val count = minOf(n - off, ib.capacity() / 2)
            ib.order(ByteOrder.nativeOrder()).asShortBuffer().put(buf, off, count)
            s.codec.queueInputBuffer(idx, 0, count * 2, s.queued * 1_000_000L / s.rate, 0)
            s.queued += count
            off += count
        }
        drain(s, info, false)
    }

    private fun endStream(s: Session, info: MediaCodec.BufferInfo) {
        val idx = s.codec.dequeueInputBuffer(100_000)
        if (idx >= 0) s.codec.queueInputBuffer(idx, 0, 0, s.queued * 1_000_000L / s.rate, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
        drain(s, info, true)
    }

    /** Writes encoded frames to the part file, each with its ADTS header. */
    private fun drain(s: Session, info: MediaCodec.BufferInfo, eos: Boolean) {
        var waits = 0
        while (true) {
            val idx = s.codec.dequeueOutputBuffer(info, if (eos) 10_000 else 0)
            if (idx >= 0) {
                if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0 && info.size > 0) {
                    val ob = s.codec.getOutputBuffer(idx)!!
                    val frame = ByteArray(Adts.HEADER + info.size)
                    Adts.header(info.size, s.rate, 1).copyInto(frame)
                    ob.position(info.offset)
                    ob.get(frame, Adts.HEADER, info.size)
                    s.part.write(frame)
                }
                s.codec.releaseOutputBuffer(idx, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
            } else if (idx == MediaCodec.INFO_TRY_AGAIN_LATER && (!eos || ++waits > 100)) {
                return
            }
        }
    }

    private fun audioManager() = app.getSystemService(AudioManager::class.java)
}
