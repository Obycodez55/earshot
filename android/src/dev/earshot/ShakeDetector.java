package dev.earshot;

import android.content.Context;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.os.PowerManager;
import android.os.SystemClock;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.util.Log;

/**
 * Calls back when the phone is shaken deliberately: three hard jolts within
 * about a second, with the screen on. Then ignores motion for a few seconds.
 */
final class ShakeDetector implements SensorEventListener {
    private static final float JOLT_G = 1.8f;        // how hard one jolt must be
    private static final int JOLTS_NEEDED = 3;
    private static final long JOLT_GAP_MS = 90;      // jolts closer than this count as one
    private static final long WINDOW_MS = 1100;      // all jolts must fall inside this
    private static final long COOLDOWN_MS = 4000;
    private static final long SETTLE_MS = 1500;
    private static final String TAG = "EarshotShake";

    private final Context context;
    private final Runnable onShake;
    private SensorManager sensors;
    private int jolts;
    private long firstJolt;
    private long lastJolt;
    /** Shared by every detector: one shake must never be acted on twice. */
    private static volatile long quietUntil;

    ShakeDetector(Context context, Runnable onShake) {
        this.context = context.getApplicationContext();
        this.onShake = onShake;
    }

    void start() {
        if (sensors != null) return;
        sensors = context.getSystemService(SensorManager.class);
        Sensor accelerometer = sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);
        if (accelerometer == null) { sensors = null; return; }
        // The shake that switched the sound is often still going when the next
        // listener starts. Don't let its tail end count as a new shake.
        quietUntil = Math.max(quietUntil, SystemClock.elapsedRealtime() + SETTLE_MS);
        sensors.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_GAME);
    }

    void stop() {
        if (sensors == null) return;
        sensors.unregisterListener(this);
        sensors = null;
        jolts = 0;
    }

    @Override
    public void onSensorChanged(SensorEvent event) {
        float x = event.values[0], y = event.values[1], z = event.values[2];
        double g = Math.sqrt(x * x + y * y + z * z) / SensorManager.GRAVITY_EARTH;
        if (g < JOLT_G) return;

        long now = SystemClock.elapsedRealtime();
        if (now < quietUntil || now - lastJolt < JOLT_GAP_MS) return;
        if (jolts == 0 || now - firstJolt > WINDOW_MS) {
            jolts = 0;
            firstJolt = now;
        }
        lastJolt = now;
        Log.i(TAG, String.format("jolt %d of %d, %.1fg", jolts + 1, JOLTS_NEEDED, g));
        if (++jolts < JOLTS_NEEDED) return;

        jolts = 0;
        quietUntil = now + COOLDOWN_MS;
        if (!context.getSystemService(PowerManager.class).isInteractive()) return;
        Log.i(TAG, "shake recognised");
        context.getSystemService(Vibrator.class)
                .vibrate(VibrationEffect.createOneShot(70, VibrationEffect.DEFAULT_AMPLITUDE));
        onShake.run();
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int accuracy) {}
}
