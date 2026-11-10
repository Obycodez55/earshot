package dev.earshot;

import android.Manifest;
import android.app.Activity;
import android.app.StatusBarManager;
import android.content.ComponentName;
import android.content.pm.PackageManager;
import android.graphics.drawable.Icon;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

/** Setup screen: add the tile, allow notifications, and a manual toggle for testing. */
public class MainActivity extends Activity {
    private TextView status;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        int pad = (int) (24 * getResources().getDisplayMetrics().density);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_VERTICAL);
        root.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText("Earshot");
        title.setTextSize(28);
        root.addView(title);

        TextView help = new TextView(this);
        help.setText("Plays this phone's sound on your Mac.\n\n"
                + "1. Open Earshot on the Mac.\n"
                + "2. Add the \"Play on Mac\" tile to Quick Settings.\n"
                + "3. Tap the tile whenever you want the sound on the Mac.");
        help.setTextSize(16);
        help.setPadding(0, pad / 2, 0, pad);
        root.addView(help);

        Button addTile = new Button(this);
        addTile.setText("Add tile to Quick Settings");
        addTile.setOnClickListener(v -> requestTile());
        root.addView(addTile);

        Button toggle = new Button(this);
        toggle.setText("Start / stop now");
        toggle.setOnClickListener(v -> send("toggle"));
        root.addView(toggle);

        Button mirror = new Button(this);
        mirror.setText("Mirror this screen on the Mac");
        mirror.setOnClickListener(v -> send("mirror"));
        root.addView(mirror);

        status = new TextView(this);
        status.setTextSize(16);
        status.setPadding(0, pad, 0, 0);
        root.addView(status);

        setContentView(root);

        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[] {Manifest.permission.POST_NOTIFICATIONS}, 1);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        send("status");
    }

    private void send(String command) {
        status.setText("Checking…");
        new Thread(() -> {
            String reply = Link.sendAndRemember(this, command);
            runOnUiThread(() -> status.setText(describe(reply)));
        }).start();
    }

    private static String describe(String reply) {
        if (reply == null) return "Mac not connected. Open Earshot on the Mac.";
        switch (reply) {
            case "on": return "Playing on the Mac.";
            case "off": return "Connected to the Mac. Not playing.";
            default: return "The Mac is running but can't see this phone yet.";
        }
    }

    private void requestTile() {
        if (Build.VERSION.SDK_INT >= 33) {
            getSystemService(StatusBarManager.class).requestAddTileService(
                    new ComponentName(this, EarshotTileService.class),
                    "Play on Mac",
                    Icon.createWithResource(this, R.drawable.ic_ear),
                    getMainExecutor(),
                    result -> {});
        } else {
            status.setText("Edit Quick Settings and drag in \"Play on Mac\".");
        }
    }
}
