package dev.earshot;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ServiceInfo;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;

/**
 * Runs only while audio is playing on the Mac. Keeps the CPU and Wi-Fi out of
 * power saving so the stream stays smooth when the screen is locked, and shows
 * an ongoing notification with a Stop button.
 * Started and stopped by the Mac through adb.
 */
public class KeepAwakeService extends Service {
    private static final String CHANNEL = "playing";
    private static final int ID = 2;
    private static final long CHECK_EVERY_MS = 30_000;

    private PowerManager.WakeLock wakeLock;
    private WifiManager.WifiLock wifiLock;
    private WifiManager.WifiLock lowLatencyLock;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private int missedChecks;
    private boolean watchingScreen;
    private ShakeDetector shake;

    /** Tells the Mac when the screen goes off or on, so it can pick the right buffer. */
    private final BroadcastReceiver screenWatcher = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            report(Intent.ACTION_SCREEN_OFF.equals(intent.getAction()));
        }
    };

    private void report(boolean screenOff) {
        new Thread(() -> Link.send(screenOff ? "locked" : "unlocked")).start();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        startForeground(ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE);
        acquire();
        if (!watchingScreen) {
            IntentFilter filter = new IntentFilter(Intent.ACTION_SCREEN_OFF);
            filter.addAction(Intent.ACTION_SCREEN_ON);
            registerReceiver(screenWatcher, filter);
            watchingScreen = true;
        }
        if (!getSystemService(PowerManager.class).isInteractive()) report(true);

        // While playing on the Mac, a shake brings the sound back to the phone.
        boolean wantShake = intent != null && intent.getBooleanExtra("shake", false);
        if (wantShake && shake == null) {
            shake = new ShakeDetector(this,
                    () -> new Thread(() -> Link.sendAndRemember(this, "stop")).start());
            shake.start();
        } else if (!wantShake && shake != null) {
            shake.stop();
            shake = null;
        }
        handler.removeCallbacksAndMessages(null);
        handler.postDelayed(this::checkMac, CHECK_EVERY_MS);
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        if (shake != null) shake.stop();
        shake = null;
        if (watchingScreen) {
            unregisterReceiver(screenWatcher);
            watchingScreen = false;
        }
        release();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @SuppressWarnings("deprecation")
    private void acquire() {
        if (wakeLock == null) {
            wakeLock = getSystemService(PowerManager.class)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "earshot:stream");
            wakeLock.acquire(6 * 60 * 60 * 1000L);
        }
        WifiManager wifi = getApplicationContext().getSystemService(WifiManager.class);
        if (wifiLock == null) {
            wifiLock = wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "earshot:stream");
            wifiLock.acquire();
        }
        if (lowLatencyLock == null) {
            lowLatencyLock = wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_LOW_LATENCY, "earshot:lowlatency");
            lowLatencyLock.acquire();
        }
    }

    private void release() {
        if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        if (wifiLock != null && wifiLock.isHeld()) wifiLock.release();
        if (lowLatencyLock != null && lowLatencyLock.isHeld()) lowLatencyLock.release();
        wakeLock = null;
        wifiLock = null;
        lowLatencyLock = null;
    }

    /** If the Mac goes away without saying so, don't keep the phone awake for nothing. */
    private void checkMac() {
        new Thread(() -> {
            boolean playing = "on".equals(Link.send("status"));
            handler.post(() -> {
                missedChecks = playing ? 0 : missedChecks + 1;
                if (missedChecks >= 2) {
                    Link.prefs(this).edit().putBoolean("on", false).apply();
                    Link.refreshTile(this);
                    stopSelf();
                } else {
                    handler.postDelayed(this::checkMac, CHECK_EVERY_MS);
                }
            });
        }).start();
    }

    private Notification buildNotification() {
        getSystemService(NotificationManager.class).createNotificationChannel(
                new NotificationChannel(CHANNEL, "Playing on Mac", NotificationManager.IMPORTANCE_LOW));
        Intent stop = new Intent(this, ActionReceiver.class).setAction(ActionReceiver.STOP);
        PendingIntent stopTap = PendingIntent.getBroadcast(this, 1, stop,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(this, CHANNEL)
                .setSmallIcon(R.drawable.ic_ear)
                .setContentTitle("Playing on your Mac")
                .setContentText("This phone's sound is coming from your Mac.")
                .setOngoing(true)
                .addAction(new Notification.Action.Builder(null, "Stop", stopTap).build())
                .build();
    }

    static Intent intent(Context context) {
        return new Intent(context, KeepAwakeService.class);
    }
}
