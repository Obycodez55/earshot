package dev.earshot;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Handles taps on the "Play this on your Mac?" suggestion and the Stop button. */
public class ActionReceiver extends BroadcastReceiver {
    static final String START = "dev.earshot.action.START";
    static final String STOP = "dev.earshot.action.STOP";

    @Override
    public void onReceive(Context context, Intent intent) {
        String command = START.equals(intent.getAction()) ? "start"
                : STOP.equals(intent.getAction()) ? "stop" : null;
        if (command == null) return;
        PendingResult pending = goAsync();
        Context app = context.getApplicationContext();
        new Thread(() -> {
            Link.sendAndRemember(app, command);
            pending.finish();
        }).start();
    }
}
