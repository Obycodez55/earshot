package dev.earshot;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.IBinder;

/**
 * Listens for a shake while something is playing on the phone and the Mac is
 * connected but idle. A shake sends the sound to the Mac.
 * The Mac starts and stops this through adb, so the motion sensor is only in
 * use when a shake could do something.
 */
public class ShakeService extends Service {
    private static final String CHANNEL = "shake";
    private static final int ID = 3;

    private ShakeDetector detector;

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        getSystemService(NotificationManager.class).createNotificationChannel(
                new NotificationChannel(CHANNEL, "Shake to play on Mac", NotificationManager.IMPORTANCE_MIN));
        Notification notification = new Notification.Builder(this, CHANNEL)
                .setSmallIcon(R.drawable.ic_ear)
                .setContentTitle("Shake to play on your Mac")
                .setOngoing(true)
                .build();
        startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE);

        if (detector == null) {
            detector = new ShakeDetector(this,
                    () -> new Thread(() -> Link.sendAndRemember(this, "start")).start());
            detector.start();
        }
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        if (detector != null) detector.stop();
        detector = null;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
