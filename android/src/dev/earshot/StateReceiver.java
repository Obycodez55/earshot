package dev.earshot;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Receives messages the Mac sends through adb: current state, and "offer to play on Mac". */
public class StateReceiver extends BroadcastReceiver {
    static final String CHANNEL = "suggest";
    static final int SUGGEST_ID = 1;

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if ("dev.earshot.STATE".equals(action)) {
            boolean on = intent.getBooleanExtra("on", false);
            Link.prefs(context).edit().putBoolean("on", on).putBoolean("reachable", true).apply();
            if (on) notifications(context).cancel(SUGGEST_ID);
            Link.refreshTile(context);
        } else if ("dev.earshot.SUGGEST".equals(action)) {
            suggest(context);
        }
    }

    private static NotificationManager notifications(Context context) {
        return context.getSystemService(NotificationManager.class);
    }

    private static void suggest(Context context) {
        NotificationManager manager = notifications(context);
        manager.createNotificationChannel(new NotificationChannel(
                CHANNEL, "Suggestions", NotificationManager.IMPORTANCE_HIGH));

        Intent start = new Intent(context, ActionReceiver.class).setAction(ActionReceiver.START);
        PendingIntent tap = PendingIntent.getBroadcast(context, 0, start,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Notification notification = new Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_ear)
                .setContentTitle("Play this on your Mac?")
                .setContentText("Tap to send the sound to your Mac's speakers.")
                .setContentIntent(tap)
                .setAutoCancel(true)
                .setTimeoutAfter(20000)
                .build();
        manager.notify(SUGGEST_ID, notification);
    }
}
