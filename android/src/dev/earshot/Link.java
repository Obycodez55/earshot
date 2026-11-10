package dev.earshot;

import android.content.ComponentName;
import android.content.Context;
import android.content.SharedPreferences;
import android.service.quicksettings.TileService;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

/**
 * Talks to the Mac app. The Mac opens `adb reverse tcp:47800`, so the Mac's
 * control port appears on this phone as localhost.
 */
final class Link {
    static final int PORT = 47800;
    private static final String PREFS = "earshot";

    private Link() {}

    /** Sends one command. Returns "on", "off", "nophone", or null if the Mac is not reachable. */
    static String send(String command) {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress("127.0.0.1", PORT), 1500);
            socket.setSoTimeout(4000);
            OutputStream out = socket.getOutputStream();
            out.write((command + "\n").getBytes(StandardCharsets.UTF_8));
            out.flush();
            BufferedReader in = new BufferedReader(
                    new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
            String reply = in.readLine();
            return reply == null ? null : reply.trim();
        } catch (Exception e) {
            return null;
        }
    }

    /** Sends a command and records the result so the tile can show it. */
    static String sendAndRemember(Context context, String command) {
        String reply = send(command);
        prefs(context).edit()
                .putBoolean("on", "on".equals(reply))
                .putBoolean("reachable", reply != null)
                .apply();
        refreshTile(context);
        return reply;
    }

    static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static void refreshTile(Context context) {
        EarshotTileService.redrawIfVisible();
        try {
            TileService.requestListeningState(context,
                    new ComponentName(context, EarshotTileService.class));
        } catch (Exception ignored) {
            // The tile has not been added to Quick Settings yet.
        }
    }
}
