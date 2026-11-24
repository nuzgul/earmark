package app.earmark.recorder.engine

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder
import android.service.quicksettings.TileService
import android.content.ComponentName
import app.earmark.recorder.R
import kotlin.concurrent.thread

/**
 * Keeps the process alive while recording (foreground service, type microphone) and puts
 * Mark / Pause / Stop in the notification, which also shows on the lock screen.
 * It never records by itself: it mirrors [RecorderEngine] and stops when the engine is idle.
 */
class RecorderService : Service(), RecorderEngine.Listener {
    companion object {
        private const val ACTION_START = "app.earmark.recorder.action.START"
        private const val ACTION_MARK = "app.earmark.recorder.action.MARK"
        private const val ACTION_PAUSE = "app.earmark.recorder.action.PAUSE"
        private const val ACTION_RESUME = "app.earmark.recorder.action.RESUME"
        private const val ACTION_STOP = "app.earmark.recorder.action.STOP"
        // Default importance (not "silent"): silent notifications are collapsed and many phones hide
        // them on the lock screen, which would hide the Mark button. The channel has no sound.
        private const val CHANNEL = "recording_session"
        private const val NOTIFICATION_ID = 1

        /** Called from the visible activity right after the engine starts (Android 14 while-in-use rule). */
        fun start(context: Context) {
            context.startForegroundService(Intent(context, RecorderService::class.java).setAction(ACTION_START))
        }

        fun timeText(ms: Long): String {
            val s = ms / 1000
            return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60) else "%02d:%02d".format(s / 60, s % 60)
        }
    }

    private var shown: List<Any?>? = null
    private var foreground = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        RecorderEngine.init(this)
        val channel = NotificationChannel(CHANNEL, "Recording", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Shows while Earmark records, with Mark, Pause and Stop."
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java).run {
            deleteNotificationChannel("recording") // Phase 1 draft channel (silent importance)
            createNotificationChannel(channel)
        }
        RecorderEngine.addListener(this)
    }

    override fun onDestroy() {
        RecorderEngine.removeListener(this)
        refreshTile()
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val n = build(RecorderEngine.snapshot())
                // FOREGROUND_SERVICE_TYPE_MICROPHONE is API 30; on 29 the manifest type applies.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
                } else {
                    startForeground(NOTIFICATION_ID, n)
                }
                foreground = true
                refreshTile()
            }
            ACTION_MARK -> RecorderEngine.markInBackground("notification") // fsync off the main thread
            ACTION_PAUSE -> RecorderEngine.pause()
            ACTION_RESUME -> RecorderEngine.resume()
            ACTION_STOP -> thread(name = "earmark-stop") { RecorderEngine.stop() }
        }
        if (!RecorderEngine.isActive) stopNow()
        return START_NOT_STICKY // a restarted service would have no session to show
    }

    override fun onSnapshot(s: EngineSnapshot) {
        // Snapshots arrive by post and can be stale (an IDLE from the last session after a new start,
        // a FINALIZING after the save), so decide from the engine's live state. Never stop before
        // startForeground ran: a service started with startForegroundService would crash.
        if (!foreground) return
        val live = RecorderEngine.liveId ?: return stopNow()
        if (s.recordingId != live) return
        val key = listOf(s.state, s.markCount, s.interruption)
        if (key == shown) return // the chronometer ticks by itself; update only on real changes
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, build(s))
    }

    private fun stopNow() {
        foreground = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun build(s: EngineSnapshot): Notification {
        shown = listOf(s.state, s.markCount, s.interruption)
        val running = s.state == SessionState.RECORDING
        val title = when (s.state) {
            SessionState.RECORDING -> "Recording"
            SessionState.PAUSED -> "Paused at ${timeText(s.positionMs)}"
            SessionState.INTERRUPTED -> if (s.interruption == "call") "Paused: call" else "Checking microphone…"
            SessionState.FINALIZING -> "Saving…"
            else -> "Starting…"
        }
        val marks = when (s.markCount) {
            0L -> "No marks yet"
            1L -> "1 mark"
            else -> "${s.markCount} marks"
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)
        val b = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_earmark)
            .setContentTitle(title)
            .setContentText(marks)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setShowWhen(running)
            .setUsesChronometer(running)
            .setWhen(System.currentTimeMillis() - s.positionMs)
            .setContentIntent(PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        if (s.state != SessionState.FINALIZING && s.state != SessionState.STARTING) {
            b.addAction(action("Mark", R.drawable.ic_action_mark, ACTION_MARK, 1))
            if (s.state == SessionState.PAUSED) b.addAction(action("Resume", R.drawable.ic_action_resume, ACTION_RESUME, 2))
            else b.addAction(action("Pause", R.drawable.ic_action_pause, ACTION_PAUSE, 2))
            b.addAction(action("Stop", R.drawable.ic_action_stop, ACTION_STOP, 3))
            // Compact layout: the three buttons are visible without expanding the notification.
            b.setStyle(Notification.MediaStyle().setShowActionsInCompactView(0, 1, 2))
        }
        return b.build()
    }

    private fun action(label: String, icon: Int, action: String, code: Int): Notification.Action {
        val pi = PendingIntent.getService(
            this, code, Intent(this, RecorderService::class.java).setAction(action),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Action.Builder(Icon.createWithResource(this, icon), label, pi).build()
    }

    private fun refreshTile() {
        TileService.requestListeningState(this, ComponentName(this, MarkTileService::class.java))
    }
}
