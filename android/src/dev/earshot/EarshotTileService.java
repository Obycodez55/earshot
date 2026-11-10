package dev.earshot;

import android.content.SharedPreferences;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/** The one-tap control: a Quick Settings tile that asks the Mac to start or stop. */
public class EarshotTileService extends TileService {
    /** The tile instance currently on screen, if any, so state changes can redraw it at once. */
    private static volatile EarshotTileService visible;

    /** Redraws the tile if the Quick Settings panel is showing it. Safe from any thread. */
    static void redrawIfVisible() {
        EarshotTileService tile = visible;
        if (tile != null) tile.getMainExecutor().execute(tile::render);
    }

    @Override
    public void onStopListening() {
        if (visible == this) visible = null;
    }

    @Override
    public void onStartListening() {
        visible = this;
        render();
        new Thread(() -> {
            Link.sendAndRemember(this, "status");
            getMainExecutor().execute(this::render);
        }).start();
    }

    @Override
    public void onClick() {
        Tile tile = getQsTile();
        if (tile != null) {
            tile.setSubtitle("Connecting…");
            tile.updateTile();
        }
        new Thread(() -> {
            Link.sendAndRemember(this, "toggle");
            getMainExecutor().execute(this::render);
        }).start();
    }

    private void render() {
        Tile tile = getQsTile();
        if (tile == null) return;
        SharedPreferences prefs = Link.prefs(this);
        boolean on = prefs.getBoolean("on", false);
        boolean reachable = prefs.getBoolean("reachable", true);
        tile.setState(on ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        tile.setLabel("Play on Mac");
        tile.setSubtitle(on ? "Playing on Mac" : reachable ? "Off" : "Mac not connected");
        tile.updateTile();
    }
}
