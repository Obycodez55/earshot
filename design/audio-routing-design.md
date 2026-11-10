# Phone → Mac audio routing: design document

Status: design, test results and a working Phase 1a build, 10 Nov 2026.
Project name: **Earshot**.

**How to read the markers**

- **[V]** verified against a primary source during this pass (link in [Sources](#sources)).
- **[S]** supported only by secondary sources or community reports.
- **[U]** unverified: from memory or my own engineering estimate. Each one is covered by a proof-of-concept in [section 12](#12-riskiest-assumptions-and-the-proof-of-concept-for-each).

---

## 1. Summary of decisions

| Topic | Decision |
|---|---|
| Sync strategy | Keep end-to-end latency under about 60 ms (hard ceiling about 100 ms). The phone's video cannot be delayed, and audio cannot be sent early, so low latency is the only lever in Phase 1. |
| Capture | Two tiers behind one interface. **Standard**: MediaProjection + AudioPlaybackCapture (works for anyone, has a consent prompt and app opt-outs). **Pro**: a shell-privileged helper in the style of scrcpy's server, using REMOTE_SUBMIX (captures everything, mutes the phone, no prompt, needs USB debugging). |
| Transport | Default: Wi-Fi LAN, custom UDP with a small RTP-like header. Fallbacks, in order: USB, phone hotspot. BLE is for discovery, proximity and wake-up only. No WebRTC. |
| Codec | Raw 16-bit 48 kHz stereo PCM by default (1.5 Mbit/s, zero codec delay). Opus at 5–10 ms frames with FEC as the automatic fallback on a lossy link. No FLAC. |
| Clock drift | Receiver-side adaptive resampling driven by jitter-buffer fill level. |
| Mac side | Native Swift menu-bar app, Core Audio output with a 128–256 frame IO buffer, Bonjour advertisement, bundled `adb` for Pro mode. Distributed with Developer ID, outside the Mac App Store. |
| One-tap UX | Quick Settings tile. Honest count: **one tap in Pro mode, two in Standard mode** (tile, then Android's own "Start" consent button, which cannot be skipped). |
| First step | Build nothing. Measure sync with stock scrcpy audio-only over USB and Wi-Fi. If that does not feel right, no amount of product work will fix it. |

**Biggest risk:** lip sync over Wi-Fi. The budget is roughly 60 ms and a jitter buffer that survives ordinary home Wi-Fi wants 20–40 ms of it. USB will very likely be fine. Wi-Fi may be fine on a good network and visibly late on a poor one.

---

## 1a. Your answers, and what they change (added 10 Nov 2026)

**Setup:** Redmi Note 15 Pro (model 25100RA69G). You said Android 15; the phone itself reports **Android 16**. Mac on macOS 27.2.1, built-in speakers. Personal tool, no store. Developer options and USB debugging are fine. Wireless matters most; a USB cable is available. Networks: home Wi-Fi or the phone's hotspot.

Where this section conflicts with the sections below, this section wins. The rest of the doc is kept as the reasoning and as the record of options not taken.

| Your answer | Consequence |
|---|---|
| Personal tool, debugging allowed | **Pro tier is the product. Standard tier is dropped.** No MediaProjection, so no consent prompt, no status-bar chip, and no stopping on lock. Phases 1b's "own Android sender" is no longer needed; the phone side is a shell helper plus a small tile app. |
| Keep notifications | Solved by the above. Notification hiding only happens during a MediaProjection session, which Pro tier never starts. |
| Chrome matters | Pro tier's whole-output capture is expected to include it **[U]** (PoC 2 confirms). |
| Wireless is very important | Default link is **adb over Wi-Fi**. USB is the fallback and the reference for measurements. See "Wireless plan" below. |
| Sync as accurate as possible | Raw PCM always on home Wi-Fi. Adaptive jitter buffer that starts at 20 ms and shrinks when the link is clean. The menu-bar shows live latency. A "Best sync (USB)" hint appears when Wi-Fi is measurably worse. |
| Built-in Mac speakers | The Bluetooth-output problem goes away. The app still warns if the output device changes to AirPods. |
| Phone volume buttons control the Mac | REMOTE_SUBMIX is reported to follow the phone's media volume **[S]**, which would give this for free: the buttons scale the stream. If the Redmi doesn't behave that way, the helper watches the phone's volume and sends it to the Mac as a gain. Checked in PoC 1. |
| Control in Phase 2 | Available, because Pro tier can inject input. On Xiaomi this needs one extra switch (below). |
| Wait for tap, may suggest | No auto-start. When the Mac sees the phone on the network and media is playing, the phone shows a "Play on Mac" suggestion notification. One tap starts. |
| Hotspot use | Works with the same link (the Mac joins the hotspot). Covered in the wireless plan. |

### Wireless plan

Two ways to get adb without a cable. Both end in the same thing: the Mac can launch the helper and open the audio tunnel over Wi-Fi.

| Method | Setup | Survives | Notes |
|---|---|---|---|
| **A. `adb tcpip 5555`** | Plug in USB once; the Mac app runs the command by itself. | Until the phone reboots. | **[U]** Listens on every interface, so it should also work when the Mac is on the phone's hotspot. Simplest and most predictable. After a reboot, plug in once for a second. |
| **B. Wireless debugging** (Developer options) | Pair once with a code, no cable ever. | **[S]** Android switches it off on reboot and when the Wi-Fi network changes. **[U]** It needs the phone to be a Wi-Fi client, so it likely does not work in hotspot mode. | Good at home; needs re-enabling by hand after each reboot. |

Plan: support A first, add B if plugging in after reboots is annoying in practice. The Mac app finds the phone by mDNS (`_adb-tls-connect._tcp` for B) or by remembering its last address (A), and reconnects by itself.

Audio runs through the adb tunnel to begin with, as scrcpy does. That tunnel is TCP, which on Wi-Fi can turn one lost packet into a longer stall ([section 5.1](#51-wi-fi-lan-default)). If PoC 1 shows stalls over Wi-Fi, the helper sends audio over direct UDP to the Mac instead and adb is used only to launch it. That is the one piece of the original Phase 1b that may still be needed.

### Things specific to this phone

- **[S]** Xiaomi/HyperOS has a separate Developer-options switch, **"USB debugging (Security settings)"**, required for input injection. Not needed for audio; needed for Phase 2 control. It asks for a Mi account sign-in and several confirmations.
- **[U]** HyperOS is aggressive about killing background apps. The tile app should be set to "No restrictions" under battery saver and allowed to autostart. The shell helper is not an app and is not subject to this.
- **[S]** HyperOS has changed scrcpy audio behaviour on some devices in the past. PoC 1 on this exact phone is the test.
- The cable is USB-C to USB-A. If the Mac only has USB-C ports, it needs an A-to-C adapter or a C-to-C cable. Any data-capable cable works; some charge-only cables don't.
- **[S]** A macOS 27 beta was reported to have a broken Local Network permission prompt. Only relevant if we add direct UDP or Bonjour; adb over Wi-Fi is an outgoing connection from the Mac and may still trigger the prompt once.

### Revised build plan

| Phase | Deliverable |
|---|---|
| **0** | PoC 1 (sync over USB, home Wi-Fi and hotspot with stock scrcpy), PoC 2 (Chrome, TikTok, WhatsApp, YouTube audible through `--audio-source=output`), PoC 4 (Wi-Fi jitter). PoCs 3 and 6 are no longer needed. |
| **1a** | Mac menu-bar app: bundles adb and the scrcpy server (or scrcpy itself), keeps the wireless adb connection alive, plays audio at the smallest stable buffer, shows latency. Phone: tiny app with a Quick Settings tile and the suggestion notification, which signals the Mac to start and stop. |
| **1b** | Only if needed: direct UDP audio path, own jitter buffer and drift resampler on the Mac, for better Wi-Fi behaviour than the adb tunnel gives. |
| **2** | Mirror with control. Largely scrcpy's existing feature set, presented in the same menu-bar app, with a mode switch between "audio only" and "mirror". |

How the phone tile reaches the Mac when the Mac is the one holding adb: the tile app sends a small authenticated message to the Mac app over the LAN (address learned from the Mac at pairing, refreshed each connection). The Mac then starts the helper. One tap on the phone, as required.

---

## 1b. Test results (10 Nov 2026)

Stock scrcpy 5.0.1, audio only, raw PCM, Mac output on built-in speakers (and briefly an external speaker). Judged by ear and eye; no frame-count measurement was taken.

Command shape: `scrcpy [--tcpip=ADDR:5555] --no-window --audio-codec=raw --audio-buffer=N`

| Link | Buffer | Sync | Sound |
|---|---|---|---|
| USB (through a dock) | 20 ms | Perfect | Faint but obvious crackles |
| USB (through a dock) | 30 ms | Perfect | Clean |
| Home Wi-Fi (5 GHz), cable unplugged | 40 ms | Correct | Clean |
| Home Wi-Fi (5 GHz), cable unplugged | 30 ms | Correct | Clean |
| Phone hotspot, no cable | 30 ms | Correct | Clean |

**What this settles**

- **Sync is achievable on this phone and Mac, wirelessly.** The biggest risk in this document is retired for home Wi-Fi and hotspot. (PoC 1, PoC 4.)
- **Default buffer: 30 ms on every link.** 20 ms underruns even on USB, so the floor is set by how the phone delivers audio, not by the network.
- **The adb tunnel is good enough over Wi-Fi.** No stalls heard. Phase 1b (direct UDP path) is not needed now; revisit only if long sessions show dropouts.
- **`adb tcpip 5555` works over the phone's hotspot.** The phone is the Mac's default gateway there, so the Mac can find it without discovery: read the gateway address and connect to port 5555.
- **REMOTE_SUBMIX capture works on HyperOS / Android 16** and mutes the phone.
- **The Xiaomi input-injection error appears as predicted** ("USB debugging (Security Settings)" needed). Audio is unaffected. Needed for Phase 2 control.
- scrcpy's hardware decoding, drift correction and buffer handling did the job as-is, which supports building Phase 1a as a wrapper and not a new pipeline.

**Confirmed by you after the runs**

- **Chrome and WhatsApp videos were audible.** Whole-output capture reaches apps that block ordinary playback capture, as hoped. (PoC 2.)
- **The phone's volume buttons changed the loudness on the Mac.** The capture follows the phone's media volume, so no extra volume-forwarding code is needed.
- **The external speaker was Bluetooth, and sync still looked right.** This is better than section 4.4 predicted. Bluetooth output normally adds 100–250 ms, so either this speaker is on the fast end or the total stayed inside what the eye tolerates for late sound. Treat it as "worked with this speaker", not as proof for every Bluetooth device; the planned warning becomes a soft note showing the measured output delay, not a block.

**Not yet confirmed**

- Behaviour over a long session (an hour or more): drift, dropouts, phone battery and heat.
- Behaviour after the phone locks, during a call, and when the Mac sleeps.
- A measured latency figure.
- The phone's home Wi-Fi address was unreachable right after switching back from hotspot; the app must rediscover the phone after a network change and not rely on a remembered address.

---

## 1c. Build status (10 Nov 2026)

Phase 1a is built and working on the real devices. See the [README](../README.md).

- **Mac menu-bar app** (`mac/`): keeps adb connected (USB, home Wi-Fi or hotspot), moves adb to Wi-Fi by itself, runs scrcpy audio-only, answers the phone's tile on a localhost-only port reached through `adb reverse`.
- **Phone app** (`android/`): "Play on Mac" Quick Settings tile and a "Play this on your Mac?" suggestion. Captures nothing itself.
- Confirmed by use: tile starts and stops the audio, the tile reflects state changed from either side, sound is clean at the 40 ms default.

**Lessons from the first day of use**

- **Two capture helpers on the phone split the audio**, which sounds sped-up and crackly. A helper is left behind when the Mac side is killed without a clean stop. The app now removes leftover helpers before every start, after every stop, on reconnect and on exit. This, not the buffer size, may explain the crackles heard at 30 ms.
- **A long-running adb daemon can lose the phone after a network change** ("No route to host" while the port is reachable). Restarting the daemon fixes it; the app does this by itself when not streaming.
- **scrcpy's first connection occasionally fails** ("Server connection failed"). The app retries once.
- **Xiaomi needs "Install via USB"** in Developer options before adb can install the phone app.
- The Mac's state messages do reach the phone app on HyperOS; no Autostart change was needed so far.

- **Locked screen makes Wi-Fi bursty.** Measured from the Mac (TCP connect times to the phone, 150 samples): awake, worst case 24 ms; locked, 4% over 30 ms and a worst case of 149 ms. A 40 ms buffer cannot absorb that. Android's Wi-Fi low-latency lock is only honoured for a foreground app with the screen on (the phone reported 0 ms of active time), and adb cannot force it without root. The app now restarts the stream with a 200 ms buffer when the screen goes off and returns to the normal buffer when it comes on. scrcpy cannot change its buffer while running, so each switch costs a second or two during which the phone's own speaker plays. The phone app also holds a CPU wake lock and shows a "Playing on your Mac" notification with Stop.
- **scrcpy wakes the phone's screen on start once input injection is allowed** (Xiaomi's "USB debugging (Security settings)"). Combined with restart-on-lock this made an endless loop: lock, restart, screen wakes, restart, screen times out. Fixed by always passing `--no-control --no-power-on`. Confirmed clean and steady by the user with the phone locked.
- **Media volume is per output device on this phone** (15 on the speaker, 14 on the capture route), so muting the phone during a restart by setting the volume does not work.
- **The real fix for both the restart gap and locked-screen bursts is our own receiver** with a buffer that resizes while playing (the Phase 1b idea), reading scrcpy's raw audio stream directly.

**Phase 2 (mirroring with control), first version.** A second stream mode in the Mac app: the same scrcpy process run with its window and input enabled (`--window-title=Earshot`, optionally `--turn-screen-off`) instead of `--no-window --no-control --no-power-on`. One helper serves both picture and sound, so the "two helpers split the audio" problem cannot arise. Mirror mode keeps a fixed buffer and ignores lock events, because a restart would close the window. Started from the Mac menu (⌘M) or the phone app's "Mirror this screen on the Mac" button; the tile and shake stop it like any stream. Needs Xiaomi's "USB debugging (Security settings)" for input.

**Still untested:** sessions of an hour or more, phone lock, incoming call, Mac sleep, the suggestion notification, and behaviour after a phone reboot (cable once, then wireless).

---

## 2. Requirements

**Must**

1. Any app's media audio (TikTok, WhatsApp videos, YouTube, browser) plays from the Mac's speakers.
2. Picture stays on the phone, and stays in sync with the sound.
3. One tap to start, one to stop. No per-app integration, no "cast" handoff.
4. No audible quality loss beyond what the source already has.
5. The phone's own speaker is silent while routing.

**Later (design for, don't build)**

6. Phase 2: mirror the whole screen to the Mac.
7. Reverse direction, Mac → phone.

**Non-goals**

- Phone calls and VoIP call audio.
- DRM bypass. If an app refuses capture, we say so.
- iPhone, Windows, multi-room.

---

## 3. Capture on Android

### 3.1 Standard tier: MediaProjection + AudioPlaybackCapture

Verified rules:

- **[V]** Introduced in Android 10. The capturing app needs `RECORD_AUDIO`, must show the `createScreenCaptureIntent()` prompt, and must be in the same user profile as the playing app (so work-profile apps are out of reach).
- **[V]** Only players whose usage is `USAGE_MEDIA`, `USAGE_GAME` or `USAGE_UNKNOWN` can be captured. Calls, notifications, ringtones and alarms are not capturable by a normal app. For this product that is the right behaviour: ringtones stay on the phone.
- **[V]** Apps targeting API 29+ are capturable **by default**. An app opts out with `android:allowAudioPlaybackCapture="false"` in its manifest, or per player with `ALLOW_CAPTURE_BY_SYSTEM` / `ALLOW_CAPTURE_BY_NONE`. The most restrictive setting wins.
- **[V]** Consent is required before every session, and a MediaProjection token is single-use. On Android 14+ reusing the intent or the token throws `SecurityException`. There is no "always allow".
- **[V]** Targeting Android 14+ requires a foreground service of type `mediaProjection`, plus the `FOREGROUND_SERVICE_MEDIA_PROJECTION` permission.
- **[V]** Android 14+ shows a "single app or entire screen" chooser by default. Passing `MediaProjectionConfig.createConfigForDefaultDisplay()` removes the chooser, leaving one confirmation button. We should do this.
- **[V]** On Android 15 QPR1+ a prominent status-bar chip is shown for the whole session, and **projection stops automatically when the screen locks**. Fine for watching video. It rules out "music with the screen off" in this tier.
- **[S]** On Android 15+ the system hides notification content and other sensitive UI while a projection is active, even when only audio is being captured. The workaround is a developer option ("Disable screen share protections"). This is a real cost of the Standard tier: while audio is routed, notification previews on the phone are blanked.
- **[S]** Android 16 and 17 added no further MediaProjection restrictions. Android 17 tightened background audio (an app touching audio in the background needs a foreground service), which we already have.
- **[V]** Only one MediaProjection session can exist at a time. Starting a screen recorder or Cast screen-share ends ours.

**What TikTok, WhatsApp and YouTube actually allow.** I could not verify this from primary sources, and I am not going to guess.

| App | Evidence found | Status |
|---|---|---|
| YouTube | Listed as "confirmed working" by RootlessJamesDSP, an app that uses exactly this API. One blog claims YouTube blocks capture; I rate the first source higher because it is a maintained compatibility list. | **[S]** probably capturable |
| TikTok | Nothing reliable either way. Screen recordings of TikTok with internal audio are commonplace, which suggests it is capturable. | **[U]** |
| WhatsApp (videos in chats/status) | Nothing reliable. The reports of "no sound" that exist concern *calls*, which are a different usage and never capturable. | **[U]** |
| Chrome | Listed as blocking capture by RootlessJamesDSP. This matters: videos watched in the browser would be silent in Standard tier. | **[S]** blocked |
| Spotify, SoundCloud | Listed as blocking. | **[S]** blocked |

This table is resolved in ten minutes on the real phone (PoC 2). Two ways to check, neither needing our app:

```bash
# 1. Read the manifest flag (absent = allowed if targetSdk >= 29)
adb shell pm path com.zhiliaoapp.musically        # TikTok; com.whatsapp; com.google.android.youtube
adb pull <path>/base.apk tiktok.apk
aapt2 dump xmltree --file AndroidManifest.xml tiktok.apk | grep -i -A1 allowAudioPlaybackCapture

# 2. Check the live player's flags while a video is playing
adb shell dumpsys audio | grep -i -B2 -A6 "players:"
# [U] In AOSP, AudioAttributes flag 0x400 = no media-projection capture, 0x1000 = no system capture.
```

The manifest flag alone is not conclusive, because an app can also opt out per player at runtime. The live test (record with any Play Store screen recorder set to "internal audio") is the real answer.

### 3.2 Silencing the phone's speaker

AudioPlaybackCapture takes a *copy*. The phone keeps playing. Options:

| Approach | Works for | Notes |
|---|---|---|
| Set media volume to 0 while routing, restore on stop | Standard tier | **[U]** Depends on capture being tapped before stream volume. scrcpy's contributors state the equivalent AudioPolicy path is "not affected by system volume" **[S]**, and existing apps appear to rely on this. Must be confirmed per device (PoC 3). Risks: some OEMs may treat volume 0 as a hard mute and hand us silence; the user sees their volume slider at zero; if we crash without restoring, the phone is left silent. |
| REMOTE_SUBMIX capture | Pro tier | **[V]** scrcpy's default `output` source uses it and it "disables device playback". The audio is re-routed instead of copied, so the speaker is silent by construction and the volume slider is untouched. |
| AudioPolicy with `ROUTE_FLAG_RENDER` | Pro tier | **[S]** With this flag "the audio no longer plays on the device itself"; with the loopback flag it keeps playing. This is how scrcpy implements `--audio-dup`. Needs `MODIFY_AUDIO_ROUTING`, which the shell user has had since Android 13. |

Whichever is used, the stop path must be defensive: restore the volume in `onDestroy`, in the MediaProjection `onStop` callback, on link loss, and on next app start if a "volume was zeroed" flag is still set.

### 3.3 Pro tier: shell privileges

How scrcpy does it, and what we borrow:

- **[V]** scrcpy pushes a small Java server to the phone and runs it with `app_process` as the shell user (uid 2000) over adb. Audio forwarding needs Android 11+, and works without workarounds on Android 12+.
- **[V]** Audio sources include `output` (REMOTE_SUBMIX, whole output, mutes the device) and `playback` (AudioPolicy-based, app opt-outs apply). `--audio-dup` needs Android 13+ and keeps the phone playing.
- **[V]** scrcpy 5.0 (October 2026) captures all usages in playback mode, because a policy registered as shell is not limited to media/game/unknown.
- **[S]** Neither method captures notification, ringtone or alarm sounds. Call audio is disputed in scrcpy's own issue tracker.
- **[U]** REMOTE_SUBMIX captures apps that opted out of playback capture, because it is a routing change at the device level and not a per-player tap. scrcpy's docs imply this by warning about opt-outs only for `playback`. Confirm with Chrome or Spotify in PoC 2.
- **[S]** A normal app cannot use REMOTE_SUBMIX: it needs `CAPTURE_AUDIO_OUTPUT`, granted only to system and shell.

What Pro tier buys: no consent prompt, no status-bar chip, no hidden notifications, survives screen lock, captures opted-out apps, mutes the phone properly. What it costs: the user must enable Developer options and USB debugging, and something must launch the helper with shell privileges.

Three ways to launch the helper:

| Launcher | One-time setup | Per-session friction | Fragility |
|---|---|---|---|
| **Mac runs bundled `adb` over USB** | Enable USB debugging, accept the Mac's key once | Plug in the cable | Lowest. This is plain scrcpy. |
| **Mac runs `adb` over Wi-Fi (wireless debugging)** | Pair once | None while wireless debugging stays on | **[S]** Android turns wireless debugging off on reboot and network change. A change to keep it on for trusted networks was reported for Android 16 QPR3 / 17 but I could not confirm it shipped. |
| **Shizuku on the phone** | Install Shizuku, start it via wireless debugging | None until reboot | **[V]** Must be restarted after every reboot. **[S]** Google has discussed restricting on-device loopback adb, which Shizuku depends on. No decision announced, but it is a platform risk. |

Recommendation: Mac-launched adb (USB first, wireless second). Skip Shizuku. It adds a third-party dependency and the most platform risk, for a benefit (no Mac involvement) we don't need, since the Mac is always part of the session anyway.

scrcpy is Apache-2.0, so its server can be reused or studied directly. **[U]** Check the licence text before bundling.

### 3.4 When an app blocks capture

Blocked capture yields silence, not an error. Detection and response:

1. **Detect.** Captured PCM is digital silence for more than about 1.5 s while `AudioManager.getActivePlaybackConfigurations()` reports an active media player. **[U]** That call exposes attributes but not the owning package to normal apps, so we can say "something is playing that we can't capture" but may not be able to name the app.
2. **Restore.** Put the phone's volume back immediately. Never leave the user with silence on both devices.
3. **Explain.** Notification: "This app doesn't allow its audio to be shared. Playing on the phone." If Pro tier is available, offer it as the fix.
4. **Don't circumvent.** No patched APKs, no accessibility-service tricks. DRM video apps (Netflix and similar) are out of scope in both tiers.

---

## 4. A/V sync: the central problem

### 4.1 Why it is hard here

In every normal case (Bluetooth headphones, Cast, AirPlay) the *player* knows about the audio delay and holds the video back to match. Here the player is a third-party app that believes audio is leaving the phone's speaker right now. The picture is on time; our audio arrives late by the full length of our pipeline. Audio can only ever be late, never early.

### 4.2 The three options

| Option | Verdict |
|---|---|
| **A. Delay the phone's video** | Not available. We don't control TikTok's renderer. The only lever that exists in Android is indirect: well-behaved players (ExoPlayer and similar) read the audio route's reported latency and delay video to match, which is why Bluetooth headphones stay in sync. Making the route report *our* latency would need a custom audio HAL or a virtual audio device, meaning root or a system image. **[U]** Out of scope, but it is the theoretically correct fix and worth knowing about. |
| **B. Stay under the perceptual threshold** | **The Phase 1 strategy.** |
| **C. Measure and compensate** | Compensation needs something to delay. In Phase 1 there is nothing. In Phase 2 the video is on the Mac too, so we delay whichever stream is early and sync becomes exact. We still *measure* in Phase 1, to show the user the number and to pick buffer sizes. |

### 4.3 The threshold

Sign convention: negative means sound lags picture, which is our case.

| Source | Sound may lag by | Status |
|---|---|---|
| ITU-R BT.1359-1, detectability | 125 ms | **[S]** widely cited, consistent across sources |
| ITU-R BT.1359-1, acceptability | 185 ms | **[S]** |
| EBU R37 | 60 ms | **[S]** |
| ATSC IS-191 | 45 ms | **[S]** sources disagree on the sign convention; magnitudes 15 lead / 45 lag are consistent |

People tolerate late sound better than early sound, because sound arriving after light is physically normal (10 m of distance is about 30 ms). That asymmetry is in our favour.

**Targets:** under 60 ms is good. 60–100 ms is acceptable for most content and noticeable on close-up speech. Over 125 ms is a failure.

### 4.4 Latency budget

All figures are my estimates **[U]** unless marked. PoC 1 replaces them with measurements.

| Stage | USB | Wi-Fi, good | Wi-Fi, poor |
|---|---|---|---|
| Capture (mixer period + AudioRecord buffer) | 10–20 | 10–20 | 10–20 |
| Packetise / encode (PCM, 5 ms packets) | 5 | 5 | 5–10 (Opus) |
| Network transit | 1–2 | 2–5 | 5–30 |
| Jitter buffer | 5–10 | 20–30 | 40–80 |
| Mac output (IO buffer + device latency, built-in speakers) | 8–15 | 8–15 | 8–15 |
| **Total** | **~30–50 ms** | **~45–75 ms** | **~70–155 ms** |

Three notes on the budget:

- **A possible credit.** The video player aligns picture to when audio leaves the phone's *speaker*, which is itself 10–40 ms after the mixer. We tap at the mixer, so we get the audio that much "early". **[U]** If real, the perceived offset is smaller than the table by that amount. It varies by device and route; measure it, don't bank on it.
- **Mac output device matters more than anything in the table.** If the Mac is playing through AirPods or any Bluetooth speaker, add 150–250 ms and sync is lost. The Mac app must read the output device's reported latency and warn. Built-in speakers, wired and USB/HDMI outputs are fine.
- **scrcpy's defaults** are a 50 ms audio buffer plus a 10 ms output buffer **[V]**, so stock scrcpy probably lands around 80–100 ms. It accepts lower values (`--audio-buffer=20`).

### 4.5 Bluetooth as the audio link

The background brief said Bluetooth "can't carry the audio". Mostly confirmed, with one correction.

- **Classic Bluetooth (A2DP):** macOS does not act as an A2DP sink, and has no supported way to become one. **[U]** I found no Apple statement either way; this rests on long-standing behaviour and the absence of any such API. Even if it worked, A2DP latency is typically 150–250 ms, which fails the sync budget by itself.
- **LE Audio:** **[S]** macOS shows no sign of LE Audio/LC3 support; Apple's stack is described as AAC and SBC only.
- **Custom stream over BLE (GATT or L2CAP channels):** Correction to the brief: bandwidth is not strictly the blocker. BLE on the 2M PHY can carry a few hundred kbit/s in practice, enough for Opus at 96–128 kbit/s, though not for PCM. **[U]** The real blockers are latency and stability: connection intervals of 7.5–30 ms, retransmissions and throughput that collapses with interference put it at 60–150 ms with frequent glitches. It would be lossy-only, worse than Wi-Fi in every respect, and a lot of work.

**Conclusion:** no Bluetooth audio path. BLE is used for discovery, proximity and waking the Mac app ([section 5.4](#54-ble-control-plane-only)).

---

## 5. Transport

### 5.1 Wi-Fi LAN (default)

**Protocol: custom UDP with an RTP-like header.** One datagram per 5 ms of audio.

```
0      1      2        4            8                  16
+------+------+--------+------------+-------------------+----------
| ver  | strm | flags  | seq (u32)  | capture_ts_us(u64)| payload
+------+------+--------+------------+-------------------+----------
strm:  0 = audio, 1 = video (Phase 2), 2 = control
capture_ts_us: sender CLOCK_MONOTONIC at capture of first sample
payload (PCM): 240 frames x 2 ch x 16-bit = 960 bytes, well under MTU
```

- A separate small TCP connection carries control: hello/capabilities, start/stop, volume, clock-offset pings, receiver statistics back to the sender.
- **Why not WebRTC.** Its jitter buffer is tuned for conversational voice and resists being pinned at 20 ms, its audio processing has to be disabled piece by piece, it wants Opus, and it brings ICE/DTLS/SDP machinery for a NAT problem we don't have on a LAN. It also weighs tens of megabytes. It would become the right choice only if we later want internet (off-LAN) streaming.
- **Why not plain RTP.** Nothing wrong with it; our header is RTP in spirit. A custom header lets us carry a 64-bit capture timestamp and a stream id for Phase 2 without extension headers. No third party needs to interoperate.
- **Why not TCP on Wi-Fi.** One lost frame stalls everything behind it (head-of-line blocking), which turns a 5 ms dropout into a 200 ms one. On USB there is no loss, so TCP is fine there.
- **Loss handling.** With PCM, conceal a lost 5 ms packet by cross-fading a repeat of the previous one. If loss stays above about 1%, switch to Opus with in-band FEC.
- **Security.** Pair once (QR code or 6-digit code), derive a shared key, encrypt and authenticate packets (ChaCha20-Poly1305 or similar). Otherwise anyone on the Wi-Fi can listen to the phone or play noise on the Mac.

**Discovery: Bonjour/mDNS.** The Mac advertises `_earshot._udp`. Platform changes to respect:

- **[V]** Android 17: apps targeting API 37 are blocked from the local network by default and need the new `ACCESS_LOCAL_NETWORK` runtime permission. Apps targeting lower SDKs get it implicitly with `INTERNET`. So one more permission prompt on first run, and it must be in the plan from day one.
- **[V]** macOS 15+: all Bonjour operations, including *advertising*, need the Local Network permission. **[S]** The prompt is unreliable for unsigned or ad-hoc-signed apps; Apple's advice is to sign with an Apple-issued identity. Budget for a Developer ID from the first shared build.

**Client isolation.** Guest networks, many office networks and some mesh/ISP routers block device-to-device traffic. mDNS fails, and so does direct UDP even with a known IP. Detection: the Mac is visible over BLE but not over mDNS, or a UDP probe to its address times out. Response: tell the user in plain words and offer the next fallback. There is no software fix on the same network.

**Wi-Fi quality notes.** 5 GHz or 6 GHz is strongly preferred. The usual sources of 50–200 ms spikes are the phone's Wi-Fi power saving and the Mac's periodic background scans (location services, AirDrop/AWDL). **[U]** Holding a `WIFI_MODE_FULL_LOW_LATENCY` Wi-Fi lock on Android helps with the first; the second cannot be fully disabled.

### 5.2 USB

Two different things are called "USB" here:

| Variant | Needs | Verdict |
|---|---|---|
| **adb tunnel** (`adb reverse` / `adb forward`) | USB debugging on | The Pro-tier transport. No loss, about 1–2 ms, immune to Wi-Fi conditions. This is what scrcpy uses. Gives the lowest achievable latency. |
| **USB tethering** (phone presents a network interface) | No debugging. One system toggle per plug-in. | **[U]** Gives a private IP link, so the same UDP protocol runs unchanged. Whether macOS recognises the phone's tethering interface without a driver depends on RNDIS vs NCM and varies by phone. Also makes the Mac route internet through the phone unless the service order is changed. Test before relying on it. |
| Android Open Accessory | Nothing, but custom USB code on the Mac | Avoid. Fiddly and poorly maintained on macOS. **[U]** |

### 5.3 Phone hotspot

The Mac joins the phone's hotspot. This creates a direct link with no router and no client isolation. Latency is comparable to good Wi-Fi. **[U]** Costs: the Mac's internet now goes through the phone's mobile data (or nowhere), and switching networks is a manual step on the Mac. It is a reasonable answer for hotels and offices, not something to automate in v1.

**[U]** Wi-Fi Direct between Android and macOS is not supported by macOS. Wi-Fi Aware arrived on iOS in 2025–26; I have not confirmed macOS support or Android interoperability. Not planned.

### 5.4 BLE: control plane only

- The Mac advertises a service UUID; the phone scans (or the reverse). This gives discovery that works even under client isolation, and RSSI as a rough "is the phone near the Mac" signal.
- Carries tiny messages: "start session", "which IP/port", "launch the adb helper now".
- Enables the "you're next to your Mac, tap to route audio" suggestion.
- Costs: Bluetooth permissions on both sides (`BLUETOOTH_SCAN`/`CONNECT` on Android, Bluetooth permission on macOS), and background scanning limits on Android. It is an enhancement, scheduled after the core works.

### 5.5 Selection order

```
start
 ├─ adb device attached over USB and Pro enabled?  → USB/adb tunnel, PCM, 5–10 ms buffer
 ├─ Mac found by mDNS on current Wi-Fi?            → UDP, PCM, adaptive 20–40 ms buffer
 │     └─ loss > 1% or jitter > 30 ms sustained?   → switch to Opus+FEC, tell the user Wi-Fi is weak
 ├─ Mac seen over BLE but unreachable by IP?       → "This network blocks device-to-device traffic.
 │                                                    Plug in USB or use your phone's hotspot."
 └─ nothing found                                  → "Open Earshot on your Mac."
```

---

## 6. Clock drift

The phone's and the Mac's audio clocks are separate crystals. "48,000 Hz" on each differs by typically 10–100 parts per million **[U]**. At 50 ppm the receiver gains or loses 3 ms of audio per minute. A 20 ms buffer drains or overflows in about 7 minutes, producing a click or a growing delay. Because our buffer is deliberately tiny, drift bites sooner than in ordinary streaming.

**Design (receiver side):**

1. Measure jitter-buffer fill in the audio callback. Smooth it heavily (time constant of several seconds) so that network jitter is not mistaken for drift.
2. A slow PI controller turns the error (fill minus target) into a resampling ratio, clamped to about ±500 ppm. A 500 ppm pitch change is under one cent, inaudible.
3. Apply the ratio with a variable-rate resampler. Since the ratio is within 0.05% of 1.0, a good polyphase or windowed-sinc interpolator is cheap. Candidates: libsoxr (variable-rate mode), libsamplerate, or Apple's `AudioConverter`. **[U]** scrcpy does the same thing with FFmpeg's `swr_set_compensation`.
4. For large errors (after a Wi-Fi stall the buffer holds 150 ms), don't wait for the controller. Drop or cross-fade-skip audio in one step to get back to target. A brief glitch beats seconds of bad sync.
5. The same resampler handles a 44.1 kHz Mac output device.

Sketch:

```c
// called once per audio callback on the Mac
double fill_ms   = ring_fill_frames(&rb) * 1000.0 / 48000.0;
smoothed        += (fill_ms - smoothed) * 0.002;          // ~5 s time constant
double err       = smoothed - target_ms;                   // + means buffer too full
integral         = clamp(integral + err * KI, -300e-6, 300e-6);
double ratio     = 1.0 + clamp(err * KP + integral, -500e-6, 500e-6);
resampler_set_ratio(rs, ratio);                            // >1 consumes input faster
if (fabs(fill_ms - target_ms) > 3 * target_ms) hard_resync(&rb, target_ms);
```

The sender's `capture_ts_us` and the control channel's ping exchange give a second, independent estimate of clock offset and drift. That is not needed in Phase 1 but is the basis of exact sync in Phase 2.

---

## 7. Codec and what "full quality" honestly means

**What exists to be captured.** **[U]** Android's mixer runs at a fixed rate, 48 kHz on nearly every phone, usually 16-bit or float stereo. Every app's audio is resampled and mixed to that before we see it. And the sources are already lossy: TikTok, WhatsApp and YouTube deliver AAC or Opus at roughly 64–256 kbit/s. There is no hi-res signal on the phone to preserve. "Full quality" therefore means: **a bit-exact copy of the phone's 48 kHz mix reaches the Mac's DAC, with nothing re-encoded.** Raw PCM delivers exactly that.

| Codec | Bitrate | Added delay | Loss resilience | Verdict |
|---|---|---|---|---|
| **Raw PCM 16-bit/48k stereo** | 1.54 Mbit/s | 0 | Poor, but concealment covers isolated losses | **Default.** Trivial for Wi-Fi and USB. No second lossy generation. |
| **Opus**, 5–10 ms frames, 160–256 kbit/s, FEC on | ~0.2 Mbit/s | 5–10 ms frame + 2.5–6.5 ms lookahead | Good | **Fallback** for weak Wi-Fi and hotspot. Transparent at these rates for already-lossy sources. Use libopus through the NDK; Android's MediaCodec Opus encoder is not built for 5 ms frames **[U]**. |
| FLAC | ~0.7–1 Mbit/s | Block-based; default blocks are tens of ms | Poor | **No.** Saves bandwidth we are not short of, adds delay we cannot afford, and gains nothing over PCM in fidelity. |
| AAC | — | 20–100+ ms depending on profile | — | No. Too slow. |

If float capture turns out to be available **[U]**, stay with 16-bit on the wire anyway: sources are 16-bit lossy material and the difference is not audible.

---

## 8. Mac side

**Form:** a menu-bar app (`MenuBarExtra` or `NSStatusItem`), no Dock icon, launch at login via `SMAppService`. Swift.

**Menu contents:** connected phone, live latency figure (ms), link type (USB / Wi-Fi), a quality indicator, output device picker, volume, "Pair a phone…", Pro-mode setup.

**Audio output.**

- Use a Core Audio output unit (AUHAL) directly, or `AVAudioEngine` with an `AVAudioSourceNode`. AUHAL gives firmer control of the IO buffer size and reported latencies.
- Set `kAudioDevicePropertyBufferFrameSize` to 128–256 frames (2.7–5.3 ms at 48 kHz).
- Render callback is real-time: no locks, no allocation, no Swift runtime surprises. Pull from a lock-free single-producer/single-consumer ring buffer; the network thread pushes.
- Read `kAudioDevicePropertyLatency` + `kAudioDevicePropertySafetyOffset` + stream latency for the current output device. Add it to the displayed figure, and **warn when the output is Bluetooth or AirPlay** ("Your Mac is playing through AirPods. Sound will be late."). Re-check on device change.
- Mix with other Mac audio normally. Do not take exclusive (hog) mode.

**Network.** `Network.framework`: `NWListener` for UDP and for the TCP control channel, with a Bonjour service attached. Handle the Local Network permission explicitly: detect denial (no inbound traffic, listener in a waiting state) and show how to enable it in System Settings.

**Pro mode.** Bundle `adb` (Apache-2.0). Watch for device attach, push the helper, start it, set up `adb reverse`/`forward`. This requires the app to be **non-sandboxed, signed with Developer ID and notarised**. The Mac App Store's sandbox would not allow driving adb. That fixes the distribution channel: direct download.

**Power.** Hold a power assertion that prevents idle sleep while a session is active. Closing the lid ends the session; the phone must notice within about 300 ms and take its audio back.

---

## 9. The one-tap UX

### 9.1 Starting

| Entry point | Standard tier | Pro tier |
|---|---|---|
| **Quick Settings tile** (primary) | Tap tile → shade collapses → Android's consent sheet → tap "Start". **Two taps.** The second is the OS's and cannot be removed. | Tap tile → phone asks the Mac (LAN or BLE) to launch the helper over adb → audio moves. **One tap.** |
| Persistent notification (optional, off by default) | Same as tile | Same as tile |
| Mac menu-bar "Pull audio from phone" | Not possible; consent must be given on the phone | **One click on the Mac, zero on the phone** |
| Auto-start near the Mac | Not possible without the consent tap. Best we can do is a "Tap to play on your Mac" notification when the Mac appears. | Possible: start automatically when the phone is on the home Wi-Fi, the Mac is awake and media begins playing. Should be opt-in. |

Tile mechanics: a `TileService` cannot start a `mediaProjection` foreground service directly. It launches a transparent activity (`startActivityAndCollapse` with a `PendingIntent` on Android 14+ **[U]**), which fires the consent intent, then starts the service with the result. The video underneath keeps playing; the consent sheet is an overlay. **[U]** Confirm that TikTok does not pause when the sheet appears (losing focus pauses some players).

### 9.2 While running

- Tile shows active state and the Mac's name. Ongoing notification with **Stop** and the current latency.
- **Volume keys.** Ideally the phone's volume buttons control the Mac's loudness. In Standard tier the phone's media volume is pinned at 0, so pressing volume-up would un-mute the phone speaker. Plan: observe volume changes, forward the delta to the Mac as a gain change, and immediately set the phone back to 0. **[U]** This may flicker the system volume panel; needs a prototype. In Pro tier (REMOTE_SUBMIX) the phone's volume may already scale the captured signal **[S]**, which would give the right behaviour for free.
- Standard tier shows Android's status-bar chip the whole time and hides notification previews. This cannot be changed and should be mentioned in onboarding so it doesn't look like a bug.

### 9.3 Interruptions

| Event | Behaviour |
|---|---|
| Phone locks | Standard: the OS ends the projection **[V]**. Restore phone volume, end session; a new start needs a new consent. Pro: keeps running. |
| Screen off, app in background | Foreground service keeps the process alive. Hold a partial wake lock and a Wi-Fi lock. Onboarding asks for battery-optimisation exemption, since aggressive OEM task killers are the main threat. |
| Incoming or outgoing call | Call audio is never captured and stays on the phone. Pause the stream on `AUDIOFOCUS_LOSS_TRANSIENT`/telephony state, resume after. |
| Ringtones, alarms, notifications | Stay on the phone in both tiers. This is desirable. |
| Mac sleeps, lid closes, Wi-Fi drops | Phone detects missing receiver reports within ~300 ms, restores its volume, shows "Disconnected from Mac". Reconnect automatically if the Mac returns within a short window (Pro) or offer a tap (Standard: the projection token is still valid as long as the session was not stopped). |
| Another app starts screen recording or casting | Our projection is revoked (`onStop`). Same handling as lock. |
| Headphones plugged into the phone | **[U]** Standard: capture continues. Stop routing and let the headphones win. Pro: REMOTE_SUBMIX behaviour with headsets differs **[S]**; test. |
| Our app crashes | On next launch, a persisted "volume was zeroed" flag triggers a restore. Pro tier's helper is a separate process; the Mac kills it when the control channel dies. |

---

## 10. Prior art and differentiation

| Product | What it does | What it doesn't solve |
|---|---|---|
| **scrcpy** (v5.0, Oct 2026) **[V]** | Mirrors and controls Android from a computer over adb. Audio since v2.0: Opus/AAC/FLAC/raw, whole-output capture that mutes the phone, audio-only mode, 50 ms default buffer, drift compensation. Free, open source. | Needs USB debugging and a terminal command. Started from the computer, not the phone. No phone-side UI, no consumer onboarding. Built for mirroring, so audio-only-with-picture-on-phone sync is not a design goal, though it should work. |
| **sndcpy** | scrcpy's predecessor for audio: an Android app using AudioPlaybackCapture, played through VLC. | Superseded. High latency (VLC buffering), app opt-outs, manual steps. |
| **AudioRelay** | Commercial, cross-platform, both directions. Phone-as-source needs Android 10 (so it uses AudioPlaybackCapture) **[S]**. Wi-Fi and USB tethering. Has a Mac client. Freemium. | The closest existing product. General-purpose "audio hub": several steps to connect, no claim of video-sync-grade latency, and its forum has recurring reports of latency spikes and USB-tethering trouble on Mac **[S]**. No Pro/shell tier, so opted-out apps stay silent. I found no independent latency measurements. |
| **SoundWire** | PC → Android ("what you hear" on the phone). | Wrong direction for our main use, no Mac server **[S]**. Relevant only to the reverse feature. |
| **Audio Share**, **SonoBus**, **Snapcast** | Open-source LAN audio tools. SonoBus is a low-latency jam tool with Android and Mac builds; Snapcast is multi-room sync. | None captures the phone's system audio as a one-tap action; they are PC-source or microphone-source tools. |
| **Samsung/Microsoft Phone Link, Google Cast, AirPlay** | Vendor ecosystems. | Cast and AirPlay are app-integrated handoff, the model the user rejected. None targets Android → Mac. |
| **RootlessJamesDSP** | Not a streamer, but the best public evidence of what AudioPlaybackCapture can and can't reach, and of the Android 15 notification-hiding side effect. | — |

**Where this product is different**

1. **Sync is the headline requirement**, with a measured latency number on screen. Everyone else treats latency as a setting.
2. **Started from the phone, in one tap**, with the Mac passive.
3. **Two capture tiers behind one tile**, so it works for anyone and works *completely* for someone willing to enable debugging.
4. **Phone speaker handled properly**, including the failure paths.
5. Phase 2 mirroring shares the same session, pairing and transport.

Honest counterpoint: Pro tier is, technically, a friendlier scrcpy audio mode. If PoC 1 shows scrcpy alone is good enough, the cheapest real product is a Mac menu-bar wrapper around scrcpy plus a phone tile that triggers it. That is exactly the proposed Phase 1a.

---

## 11. Recommended architecture

```
 ANDROID PHONE                                         MAC
 ┌───────────────────────────────────┐                ┌──────────────────────────────────┐
 │ QS tile / notification            │                │ Menu-bar app                     │
 │        │                          │   BLE (ctl)    │   pairing, status, latency       │
 │ Session controller  ◄─────────────┼────────────────┼─► Session controller             │
 │        │                          │   TCP (ctl)    │        │                         │
 │ CaptureSource (interface)         │                │   adb launcher (Pro)             │
 │  ├ Standard: MediaProjection +    │                │        │                         │
 │  │   AudioPlaybackCapture         │   UDP audio    │   Receiver → jitter buffer       │
 │  └ Pro: shell helper,             │ ══════════════►│     → drift resampler            │
 │      REMOTE_SUBMIX                │  or adb tunnel │     → Core Audio output          │
 │        │                          │                │                                  │
 │ Packetiser (PCM | Opus+FEC)       │                │ (Phase 2) video decode → window  │
 │ Sender + link monitor             │◄── receiver ───┤  synced to audio clock           │
 │ Volume guard (mute / restore)     │    reports     │ Bonjour + BLE advertiser         │
 └───────────────────────────────────┘                └──────────────────────────────────┘
```

Design rules that keep later phases cheap:

- `CaptureSource` yields timestamped PCM blocks. The rest of the pipeline cannot tell which tier produced them.
- The wire format already has a stream id and a capture timestamp, so video is an additional stream, not a new protocol.
- The transport is an interface with two implementations: datagram (UDP) and stream (adb tunnel).
- The Mac's audio clock is the master timeline on the receiving side. Phase 2 video is presented against it.

### 11.1 Phased build plan

| Phase | Deliverable | Exit criterion |
|---|---|---|
| **0. Proofs of concept** | The measurements in section 12. No product code. | Go/no-go on sync, and a filled-in app compatibility table. |
| **1a. Pro path, thin** | Mac menu-bar app that bundles scrcpy (or its server plus our own receiver) and runs audio-only at a small buffer. Phone companion with a QS tile that asks the Mac to start/stop. USB first, then wireless debugging. | The user's daily use works with one tap over USB. |
| **1b. Own pipeline** | Our Android sender (Standard tier), UDP protocol, Mac receiver with jitter buffer and drift correction, Bonjour, pairing and encryption, volume guard, blocked-app detection. | Under 80 ms on good Wi-Fi, stable for an hour, no drift clicks. |
| **1c. Polish** | Opus fallback, link monitor and automatic switching, BLE discovery and proximity suggestion, onboarding, interruption handling, Mac output-device warning. | Survives lock, call, Wi-Fi drop and Mac sleep without leaving the phone silent. |
| **2. Mirroring** | See below. | Phone screen in a Mac window with exact A/V sync. |
| **3. Reverse** | Mac → phone audio. | — |

### 11.2 Phase 2: full-screen mirroring

- **Capture.** Standard: the same MediaProjection token already covers the screen. `createVirtualDisplay()` onto a `MediaCodec` input surface. (Note the single-use rule: audio and video must come from the *same* token and one `createVirtualDisplay` call.) Pro: scrcpy's approach, creating the display capture with shell privileges through `SurfaceControl`/`DisplayManager` hidden APIs, with no prompt. `FLAG_SECURE` windows are black in both.
- **Encode.** Hardware H.264 as the safe default; H.265 where both ends support it (better quality per bit; every Apple-silicon Mac decodes it). Low-latency settings: no B-frames, short or infinite GOP with on-demand keyframes, `KEY_LOW_LATENCY`, CBR or capped VBR at 4–12 Mbit/s for 1080p. **[V]** scrcpy 5.0 also supports AV1 and VP8/VP9 and decodes on the host GPU.
- **Transport.** Video does not tolerate loss the way audio does: a lost packet corrupts every frame until the next keyframe. Over the adb tunnel use the reliable stream, as scrcpy does. Over Wi-Fi use either a reliable stream (TCP or QUIC) with a "drop to the newest keyframe when behind" policy, or UDP with NACK retransmission and keyframe requests. Start with the reliable stream; it is far less work.
- **Decode and present.** VideoToolbox → `AVSampleBufferDisplayLayer` or Metal, in a resizable window.
- **Sync becomes exact.** Both streams carry capture timestamps from the same phone clock. The Mac presents video frame *t* when audio sample *t* reaches the speaker. Video is usually the later stream (encode + decode is 30–60 ms), so audio gets delayed slightly to match. The jitter buffer can then be larger and more robust than in Phase 1, because total delay no longer matters for sync, only for interactivity.
- **Mode switch.** "Audio only" (picture on phone, minimum latency) and "Mirror" (picture on Mac, synced) are two modes of one session. In Mirror mode the phone's screen can be dimmed.
- **Control** (mouse/keyboard to the phone) is possible only in Pro tier, through input injection as shell. Standard tier is view-only unless an accessibility service is added, which is a separate decision.

### 11.3 Reverse direction (Mac → phone), brief

- **Capture on the Mac.** **[U]** Core Audio process taps (macOS 14.2+) or ScreenCaptureKit audio capture give system audio without a virtual driver; both need a user permission (system audio / screen recording). Muting the Mac's own output is supported by taps.
- **Play on the phone** with AAudio/Oboe in low-latency mode. If the phone outputs to Bluetooth earbuds, their 150–250 ms breaks sync with the Mac's picture, and the Mac's video can't be delayed either. This is the same problem mirrored, with a worse output device.
- Same protocol, roles swapped. Cheap to add once Phase 1b exists, but the Bluetooth-earbud case (the most likely reason to want it) is the case it serves worst.

---

## 12. Riskiest assumptions and the proof-of-concept for each

Ordered by how much of the plan dies if the assumption is false. PoCs 1–3 need no code and should be done in one sitting.

| # | Assumption | Proof of concept | Pass | If it fails |
|---|---|---|---|---|
| 1 | **Sync is achievable.** Phone picture + Mac sound feels in sync. | Install scrcpy 5.x. Run `scrcpy --no-window --audio-codec=raw --audio-buffer=20` over USB, then again with `--tcpip` over Wi-Fi. Play a sync-test video (flash + beep) and ordinary talking-head clips in YouTube and TikTok on the phone. Judge by eye, then measure: film the phone screen with a second camera at 120/240 fps while recording the Mac's speakers, and count frames between flash and beep. Repeat with `--audio-buffer` 10/20/40/60. | USB ≤ 60 ms and feels right. Wi-Fi ≤ 100 ms with no dropouts at the chosen buffer. | USB fails: the product concept is not viable as specified; only Phase 2 (mirror with synced video) remains. Wi-Fi fails but USB passes: ship USB-first and label Wi-Fi "may be slightly late". |
| 2 | **The target apps are capturable in Standard tier.** | On the user's phone, record TikTok, a WhatsApp chat video, a WhatsApp status, YouTube, Chrome and Instagram with a Play Store screen recorder set to internal audio. Note which are silent. Cross-check with the `aapt2`/`dumpsys` commands in 3.1. Then repeat the silent ones with scrcpy `--audio-source=output` to confirm Pro tier reaches them. | TikTok, WhatsApp, YouTube all audible. | Any of the three silent: Standard tier cannot meet the brief alone and Pro tier becomes the main path, not the option. |
| 3 | **Media volume 0 silences the speaker but not the capture.** | During the same screen-recorder test, set media volume to 0 and check the recording still has full-level audio. Try on at least one non-Pixel phone if available. | Full-level audio in the recording. | Standard tier has no way to silence the phone. It would only be usable with the phone's speaker audibly doubling the Mac, which is unacceptable. Pro tier only. |
| 4 | **The user's Wi-Fi is good enough and not isolated.** | `ping` the Mac from the phone (Termux or adb shell) for 10 minutes while both are in normal use. Record median, 99th percentile and maximum. Then run PoC 1's Wi-Fi leg for 30 minutes and count dropouts. | 99th percentile < 15 ms, rare spikes. | Larger jitter buffer (more lag), or default to USB at the desk. |
| 5 | **Drift correction is inaudible and holds a 20 ms buffer indefinitely.** | scrcpy already does this: leave PoC 1 running for 2 hours on music with sustained tones and listen for clicks or pitch wobble. Check `--audio-buffer` target is still met at the end. | No clicks, latency unchanged after 2 h. | Need a better resampler/controller than planned; a known, solvable problem. |
| 6 | **The Standard-tier start flow is acceptable.** Tile → consent → audio moves, the video does not pause, and the side effects (status chip, hidden notification previews, stops on lock) are tolerable. | A 100-line throwaway Android app: tile → transparent activity → consent → foreground service that just captures and writes peak level to logcat. Try it on top of TikTok and YouTube. Run on Android 15+ to see the chip and notification hiding. | Video keeps playing through the prompt; the user shrugs at the side effects. | Pro tier becomes the default experience. |
| 7 | **The user accepts Developer options + USB debugging on their phone.** | Ask (open question 3). Some banking apps complain when USB debugging is on. | "Yes." | Standard tier only, with all its limits. |
| 8 | **macOS will let a menu-bar app advertise and receive on the LAN reliably.** | Minimal signed Swift app: `NWListener` + Bonjour + UDP echo; discover and ping it from the phone (`NsdManager`). Test after reboot and after toggling the Local Network switch. | Discovered within 2 s every time. | Fall back to BLE discovery plus a manually pinned IP. |
| 9 | **Mac output adds ≤ 15 ms on built-in speakers.** | Inside PoC 1's measurement, or separately: play a click through a 128-frame AUHAL and record with the Mac's mic; subtract. | ≤ 15 ms. | Budget shrinks; nothing to fix except pushing the buffer down further. |

---

## 13. Things marked unverified, in one place

1. Whether TikTok and WhatsApp (and, with less doubt, YouTube) permit playback capture today. (PoC 2)
2. Whether media volume 0 leaves captured audio at full level, on the user's phone specifically. (PoC 3)
3. Whether REMOTE_SUBMIX captures apps that opted out of playback capture. (PoC 2)
4. Every number in the latency budget, and the "mixer tap is early" credit. (PoC 1, 9)
5. That macOS cannot be an A2DP sink or LE Audio receiver: no Apple statement found; based on absence of any API and on secondary sources.
6. BLE throughput/latency figures for a custom audio stream: my estimates.
7. USB tethering to macOS working without a driver; Wi-Fi Aware on macOS.
8. Whether Android 16 QPR3/17 actually shipped "keep wireless debugging on for trusted networks".
9. AOSP flag values quoted for `dumpsys audio`, and the tile → activity launch details on Android 14+.
10. Typical crystal drift (10–100 ppm) and that scrcpy uses `swr_set_compensation`: from memory.
11. macOS process taps / ScreenCaptureKit details for the reverse direction: from memory.
12. Lip-sync figures are from secondary sources quoting ITU/EBU/ATSC documents; I did not read the primary standards. The ATSC sign convention is reported inconsistently.
13. scrcpy's licence terms for bundling; AudioRelay's internals.

---

## 14. Open questions for you

**All twelve were answered on 10 Nov 2026; see [section 1a](#1a-your-answers-and-what-they-change-added-10-nov-2026).** Remaining questions:

- A. After a phone reboot, is plugging the cable in once acceptable (method A), or should it be fully cable-free even if that means re-enabling wireless debugging by hand (method B)?
- B. Does your Mac have a USB-A port, or only USB-C?
- C. Is your home Wi-Fi 5 GHz, and are the phone and Mac usually in the same room as the router?

Original list, for the record:

1. **Which phone and which Android version?** Android 15+ changes Standard tier a lot (status chip, hidden notifications, stops on lock). The OEM matters too: Samsung, Xiaomi and others treat volume, background apps and USB differently.
2. **Which Mac and macOS version, and how do you listen on it?** Built-in speakers and wired outputs are fine. If the Mac usually plays through AirPods or a Bluetooth speaker, sync is not achievable in Phase 1.
3. **Are you willing to turn on Developer options and USB debugging on your phone?** This decides whether Pro tier (one tap, everything captured, phone muted properly) is available to you.
4. **Is this a tool for yourself, or a product for other people (Play Store)?** For yourself, Phase 1a may be all you need, within days. For the Play Store, Standard tier is mandatory, Pro tier has to be an optional extra, and the Mac app needs a paid Apple developer account for signing.
5. **Is a USB cable at your desk acceptable as the best-quality mode,** with Wi-Fi as the convenient-but-slightly-later mode? Or is wireless a hard requirement?
6. **Where will you use it?** Home Wi-Fi only, or also office/hotel/guest networks (which often block device-to-device traffic)?
7. **How sensitive are you to lip sync?** Would 80–100 ms on Wi-Fi be acceptable for TikTok-style content, or does it need to be imperceptible on close-up speech?
8. **Should the phone's volume buttons control the Mac's volume** while routing, or is controlling volume on the Mac fine?
9. **Is losing notification previews on the phone while routing (Standard tier, Android 15+) acceptable?**
10. **For Phase 2, do you want to control the phone from the Mac** (click, type), or only view it? Control is Pro-tier only.
11. **Does Chrome matter?** Videos in the browser are likely silent in Standard tier.
12. **Should it ever start by itself** (phone near Mac, video starts playing), or always wait for your tap?

---

## Sources

Android

- [Capture video and audio playback (AudioPlaybackCapture rules, opt-out table)](https://developer.android.com/media/platform/av-capture)
- [Media projection (consent per session, FGS type, status-bar chip, stop on lock, single-app sharing)](https://developer.android.com/media/grow/media-projection)
- [Foreground service types](https://developer.android.com/guide/components/fg-service-types)
- [Local network permission (Android 17, ACCESS_LOCAL_NETWORK)](https://developer.android.com/privacy-and-security/local-network-permission)
- [Android 17 features and changes](https://developer.android.com/about/versions/17/summary)
- [RootlessJamesDSP (app compatibility list, Android 15 notification hiding)](https://github.com/timschneeb/RootlessJamesDSP)
- [Shizuku user manual (restart after reboot)](https://shizuku.rikka.app/guide/setup/)
- [Report on possible loopback-adb restrictions](https://android.gadgethacks.com/news/android-on-device-adb-changes-how-google-may-restrict-loopback-access/)
- [Android Authority: wireless adb auto-reconnect report](https://www.androidauthority.com/android-wireless-adb-auto-reconnect-3624945)

scrcpy

- [scrcpy audio documentation](https://github.com/Genymobile/scrcpy/blob/master/doc/audio.md)
- [scrcpy v5.0 release notes](https://github.com/Genymobile/scrcpy/releases/tag/v5.0)
- [Issue #4380: alternative audio capture API (AudioPolicy vs REMOTE_SUBMIX)](https://github.com/Genymobile/scrcpy/issues/4380)
- [PR #6975: capture more audio usages](https://github.com/Genymobile/scrcpy/pull/6975)
- [Issue #5143: audio issue report](https://github.com/Genymobile/scrcpy/issues/5143)
- [sndcpy issue #113: restricted apps](https://github.com/rom1v/sndcpy/issues/113)

Lip sync

- [Audio-to-video synchronization (Wikipedia; ITU-R BT.1359, ATSC, EBU figures)](https://en.wikipedia.org/wiki/Audio-to-video_synchronization)
- [TV Technology: Managing lip sync](https://www.tvtechnology.com/opinions/managing-lip-sync-267386)
- [TV Technology: A/V synchronization, how bad is bad](https://www.tvtechnology.com/opinions/av-synchronization-how-bad-is-bad)

macOS and Bluetooth

- [Apple TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- [Eclectic Light: How local network privacy could affect you](https://eclecticlight.co/2026/01/14/how-local-network-privacy-could-affect-you/)
- [Apple Developer Forums: Local Network prompt not appearing on Sequoia/Tahoe](https://developer.apple.com/forums/thread/814226)
- [Apple Developer Forums: iOS and macOS support of Bluetooth LC3](https://developer.apple.com/forums/thread/829759)

Prior art

- [AudioRelay FAQ](https://docs.audiorelay.net/faq) and [community forum](https://community.audiorelay.net/c/support/5)
- [AlternativeTo: AudioRelay alternatives (Audio Share, SonoBus, Snapcast, SoundWire)](https://alternativeto.net/software/audiorelay/)
