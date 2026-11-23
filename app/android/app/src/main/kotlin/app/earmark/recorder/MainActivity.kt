package app.earmark.recorder

import app.earmark.recorder.engine.EngineSnapshot
import app.earmark.recorder.engine.FlutterError
import app.earmark.recorder.engine.MarkResult
import app.earmark.recorder.engine.RecorderHostApi
import app.earmark.recorder.engine.SessionState
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RecorderHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, PendingEngine)
    }
}

// ponytail: Phase 0 placeholder so the bridge is wired end to end; Phase 1 replaces it with the real engine.
private object PendingEngine : RecorderHostApi {
    private fun notReady(): Nothing =
        throw FlutterError("engine_not_ready", "Recording is not built yet.", null)

    override fun snapshot() = EngineSnapshot(SessionState.IDLE, null, 0, 0.0, 0, null)
    override suspend fun start(): EngineSnapshot = notReady()
    override fun pause(): EngineSnapshot = notReady()
    override fun resume(): EngineSnapshot = notReady()
    override suspend fun stop(): EngineSnapshot = notReady()
    override fun mark(): MarkResult = notReady()
}
