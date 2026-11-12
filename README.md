# Earshot

Play whatever is on your Android phone through your Mac's speakers, with one tap.
The picture stays on the phone; the sound moves to the Mac, in sync.

It works with any app (YouTube, TikTok, WhatsApp, Chrome, games), because it captures the
phone's whole audio output instead of integrating with individual apps. It can also mirror
the phone's screen in a window on the Mac, with mouse and keyboard control. No cable is needed
after setup: it runs over your Wi-Fi or the phone's hotspot.

> A personal tool, built for one phone (Redmi Note 15 Pro, Android 16) and one Mac
> (Apple silicon, macOS 27). It should work on other Android 12+ phones, but that is untested.

## How it works

```
Phone                                    Mac
"Play on Mac" tile ──localhost:47800───► Earshot menu-bar app
   (through an adb reverse tunnel)         │ keeps adb connected (USB, Wi-Fi or hotspot)
                                           │ runs scrcpy, audio only, raw PCM
phone audio ◄─── scrcpy server ────────────┘ plays through the Mac's output
```

Earshot is a thin layer over [scrcpy](https://github.com/Genymobile/scrcpy), which does the
capture, transport and playback. scrcpy's helper runs on the phone with adb shell privileges,
which is what lets it capture every app, silence the phone's own speaker, and skip Android's
screen-capture consent prompt.

- **[mac/](mac/)**: a Swift menu-bar app. It finds the phone, moves adb onto Wi-Fi, starts and stops
  scrcpy, and answers the phone's tile on a port bound to localhost only.
- **[android/](android/)**: a small app with a Quick Settings tile, a "Play this on your Mac?"
  suggestion, shake detection, and a service that keeps the phone awake while playing. It captures nothing itself.

The phone never needs the Mac's address. The Mac opens `adb reverse`, so the phone talks to
`127.0.0.1` and adb carries it across. Nothing listens on the network.

## Requirements

- **Mac**: a recent [scrcpy](https://github.com/Genymobile/scrcpy) (tested with 5.0.1) and `adb`.
  `brew install scrcpy` and `brew install --cask android-platform-tools`
- **Phone**: Android 12 or later, with Developer options → **USB debugging** turned on.
- **Xiaomi / HyperOS** also needs **Install via USB**, and **USB debugging (Security settings)**.
- To build: Xcode command-line tools, a JDK, and Android build-tools 35 with platform 35.

## Build and install

```sh
mac/install.sh                                 # builds, installs to /Applications, opens at login
android/build.sh                               # -> android/build/earshot.apk
adb install -r android/build/earshot.apk       # phone connected by USB
```

`mac/build.sh` alone builds `mac/build/Earshot.app` without installing it.

On the phone, open Earshot once, tap **Add tile to Quick Settings**, and allow notifications.

### Optional: sign with a fixed identity

By default the Mac app is ad-hoc signed, so macOS treats every rebuild as a new app and may
ask for the same permissions again. To avoid that, create a certificate once:

1. Open **Keychain Access** → menu **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Name: `Earshot Local`. Identity Type: **Self-Signed Root**. Certificate Type: **Code Signing**. Create.
3. Run `mac/install.sh` again. It prints `Signed with "Earshot Local"` when it has used it.
   macOS asks once for permission to use the key; choose **Always Allow**.

The phone app is built with the SDK tools directly (`aapt2`, `javac`, `d8`, `apksigner`), so there
is no Gradle project.

## Daily use

1. Earshot sits in the Mac's menu bar (ear icon).
2. Tap the **Play on Mac** tile on the phone. Tap again to bring the sound back.
3. Or **shake the phone** (three quick jolts). It vibrates and the sound moves to the Mac.
   Shake again to bring it back.
4. You can also start and stop from the Mac's menu. The tile follows.
5. To see and control the phone on the Mac, choose **Mirror Phone Screen** from the menu (⌘M).
   The phone's screen opens in a window with its sound; click, scroll and type into it.
   Close the window, or choose **Switch to Audio Only**, to go back.
6. The phone's volume buttons control how loud it is on the Mac.

After a phone reboot, plug the USB cable in for a few seconds. Earshot switches adb back to
Wi-Fi by itself; then unplug. The Mac app takes a few seconds after launching to find the phone.

## Menu options

| Option | What it does |
|---|---|
| **Buffer** | How much audio the Mac holds in reserve. 40 ms is the default. Lower is tighter lip sync but may crackle; higher survives weaker Wi-Fi. Applies from the next start. |
| **Turn Phone Screen Off While Mirroring** | Keeps the phone's display dark while its screen is shown on the Mac. Applies from the next time mirroring starts. |
| **Pause Mac Media While Phone Plays** | If something is playing on the Mac when the phone's sound arrives, Earshot pauses it, and resumes it when the sound goes back to the phone. It only resumes what it saw go quiet after its own pause, so it never starts something you had stopped yourself. |
| **Shake Phone to Switch** | Shake to send the sound to the Mac, shake again to bring it back. The phone only listens for shakes while the Mac is connected and something is playing (or just stopped), so the motion sensor isn't running all day. Ignored while the screen is off. |
| **Smoother Sound While Phone Is Locked** | With the screen off there is no picture to sync with, and the phone's Wi-Fi becomes bursty. Earshot restarts the stream with a 200 ms buffer when the screen goes off and returns to the normal buffer when it comes on. Each switch takes a second or two, during which the sound comes from the phone. |
| **Suggest on Phone When Media Starts** | Shows "Play this on your Mac?" on the phone when something starts playing while the Mac is connected and idle. At most once every five minutes. |
| **Open at Login** | Starts Earshot with the Mac. |

scrcpy's output is logged to `~/Library/Logs/Earshot/scrcpy.log`.

## Measured on the test devices

Judged by ear and eye, not instruments.

| Link | Buffer | Result |
|---|---|---|
| USB | 20 ms | In sync, faint crackles |
| USB | 30 ms | In sync, clean |
| Home Wi-Fi (5 GHz) | 30–40 ms | In sync, clean |
| Phone hotspot | 30 ms | In sync, clean |
| Wi-Fi, phone locked | 40 ms | Crackles (network gaps of up to ~150 ms) |
| Wi-Fi, phone locked | 200 ms | Clean |

## Known limits

- Needs USB debugging, and one cable plug-in after each phone reboot.
- Phone calls are not routed. Ringtones and notification sounds stay on the phone.
- Starting Earshot stops any other scrcpy session on the same phone. Two capture helpers
  split the audio between them, which sounds sped-up and crackly, so leftovers are removed.
- Unless you create the signing certificate above, macOS treats each rebuild of the Mac app
  as a new app and may repeat permission prompts.
- Pausing the Mac's own media works for apps that respond to the keyboard's play/pause key
  (Music, Spotify, browsers, video players). Games and command-line players keep playing.
  Browsers hold their audio output open for about ten seconds after pausing, so a phone
  session shorter than that may not resume the Mac's media afterwards.
- A Mac playing through Bluetooth headphones adds its own delay and may break lip sync.
- Mirroring is scrcpy's own window. Apps that block screen capture (banking, some video apps)
  show black. Typing passes through the Mac keyboard as text.
- Switching between audio-only and mirroring restarts the stream, so the phone's speaker plays
  for a second or two in between.

## Design notes

[design/audio-routing-design.md](design/audio-routing-design.md) has the full reasoning: why
Bluetooth can't carry the audio, the lip-sync budget, the options that were rejected, test
results, and the bugs found on the first day of use.

## Licence

[MIT](LICENSE).

## Credits

All the hard parts are [scrcpy](https://github.com/Genymobile/scrcpy) by Genymobile and Romain Vimont.
