package app.earmark.recorder.engine

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** Quick Settings tile: one tap marks the running recording, also from the lock screen. */
class MarkTileService : TileService() {
    override fun onStartListening() {
        RecorderEngine.init(this)
        refresh(null)
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    override fun onClick() {
        RecorderEngine.init(this)
        if (RecorderEngine.isActive) {
            runCatching { RecorderEngine.mark("tile") }
                .onSuccess { refresh("Mark ${it.index} · ${RecorderService.timeText(it.positionMs)}") }
            return
        }
        // Not recording: open the app (recording can only start from the visible app).
        val open = packageManager.getLaunchIntentForPackage(packageName)!!.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_IMMUTABLE))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(open)
        }
    }

    private fun refresh(subtitle: String?) {
        val tile = qsTile ?: return
        val active = RecorderEngine.isActive
        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Mark moment"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = subtitle ?: if (active) "Tap to mark" else "Not recording"
        }
        tile.updateTile()
    }
}
