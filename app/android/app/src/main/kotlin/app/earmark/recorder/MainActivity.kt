package app.earmark.recorder

import android.Manifest
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import app.earmark.recorder.engine.EngineSnapshot
import app.earmark.recorder.engine.FlutterError
import app.earmark.recorder.engine.MarkResult
import app.earmark.recorder.engine.RecorderEngine
import app.earmark.recorder.engine.RecorderEvents
import app.earmark.recorder.engine.RecorderHostApi
import app.earmark.recorder.engine.RecorderService
import app.earmark.recorder.engine.SavedRecording
import app.earmark.recorder.engine.SessionState
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** Bridges the Flutter UI to [RecorderEngine] and owns the microphone permission request. */
class MainActivity : FlutterActivity(), RecorderEngine.Listener {
    private val scope = MainScope()
    private var events: RecorderEvents? = null
    private var permissionAnswer: CompletableDeferred<Unit>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RecorderEngine.init(this)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        RecorderHostApi.setUp(messenger, Host())
        events = RecorderEvents(messenger)
        RecorderEngine.addListener(this)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        RecorderEngine.removeListener(this)
        events = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    override fun onSnapshot(s: EngineSnapshot) = send { it.onSnapshot(s) }
    override fun onMark(m: MarkResult) = send { it.onMark(m) }
    override fun onSaved(r: SavedRecording) = send { it.onSaved(r) }

    private fun send(block: suspend (RecorderEvents) -> Unit) {
        val e = events ?: return
        scope.launch {
            try {
                block(e)
            } catch (_: Exception) {
                // The Dart side is not listening yet (startup) or is gone; the next heartbeat repeats the state.
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSIONS) permissionAnswer?.complete(Unit)
    }

    private fun granted(p: String) = checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    /** Asks on the first Record tap only; notifications are asked in the same dialog sequence. */
    private suspend fun ensureMic(): Boolean {
        if (granted(Manifest.permission.RECORD_AUDIO)) return true
        val ask = mutableListOf(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) ask += Manifest.permission.POST_NOTIFICATIONS
        val answer = CompletableDeferred<Unit>().also { permissionAnswer = it }
        requestPermissions(ask.toTypedArray(), PERMISSIONS)
        answer.await()
        return granted(Manifest.permission.RECORD_AUDIO)
    }

    private inner class Host : RecorderHostApi {
        override fun snapshot() = RecorderEngine.snapshot()

        override suspend fun start(): EngineSnapshot {
            if (!ensureMic()) {
                val permanent = !shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)
                throw FlutterError("mic_denied", "Earmark needs the microphone to record.", if (permanent) "permanent" else null)
            }
            RecorderEngine.start()
            RecorderService.start(this@MainActivity)
            // "Recording" only once the microphone actually delivers audio.
            withTimeoutOrNull(3000) {
                while (RecorderEngine.snapshot().state == SessionState.STARTING) delay(10)
            }
            if (RecorderEngine.snapshot().state == SessionState.STARTING) {
                withContext(Dispatchers.IO) { RecorderEngine.stop() }
                throw FlutterError("mic_busy", "The microphone didn't start. Close other apps that use it and try again.")
            }
            return RecorderEngine.snapshot()
        }

        override fun pause() = RecorderEngine.pause()
        override fun resume() = RecorderEngine.resume()
        override fun mark() = RecorderEngine.mark("app")
        override suspend fun stop() = withContext(Dispatchers.IO) { RecorderEngine.stop() }
        override suspend fun recover() = withContext(Dispatchers.IO) { RecorderEngine.recover() }

        override fun openAppSettings() {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))
        }

        override fun useTestTone(on: Boolean) {
            RecorderEngine.testTone = on && (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        }
    }

    private companion object {
        const val PERMISSIONS = 7
    }
}
