import Foundation
import SwiftUI

struct Phone: Equatable {
    let serial: String
    var isWireless: Bool { serial.contains(":") || serial.contains("_adb-tls-connect") }
    var label: String { isWireless ? "Wi-Fi (\(serial.split(separator: ":").first ?? ""))" : "USB" }
}

/// Keeps an adb link to the phone alive, starts and stops the audio stream,
/// and answers the phone's Quick Settings tile.
@MainActor
final class Engine: ObservableObject {
    static let adbPort = 5555

    @Published private(set) var phone: Phone?
    @Published private(set) var streaming = false
    @Published private(set) var problem: String?

    @Published var bufferMs: Int {
        didSet { UserDefaults.standard.set(bufferMs, forKey: "bufferMs") }
    }
    @Published var suggest: Bool {
        didSet { UserDefaults.standard.set(suggest, forKey: "suggest") }
    }

    @Published var shakeToSwitch: Bool {
        didSet { UserDefaults.standard.set(shakeToSwitch, forKey: "shakeToSwitch") }
    }
    @Published var bigBufferWhenLocked: Bool {
        didSet { UserDefaults.standard.set(bigBufferWhenLocked, forKey: "bigBufferWhenLocked") }
    }

    private var adb: String?
    private var scrcpy: String?
    private var stream: Process?
    private var server: ControlServer?
    private var loop: Task<Void, Never>?

    private var tick = 0
    private var usbSwitchAttempted: Set<String> = []
    private var mediaWasPlaying = false
    private var shakeArmed = false
    private var quietPolls = 0
    private var lastSuggestion = Date.distantPast
    private var lastStop = Date.distantPast
    private var streamStarted = Date.distantPast
    private var streamAttempt = 0
    private var stopRequested = false
    private var lastDaemonRestart = Date.distantPast

    /// With the screen off there is no picture to stay in sync with, and the phone's
    /// Wi-Fi delivers audio in uneven bursts, so a much larger buffer is used.
    static let lockedBufferMs = 200
    private var phoneLocked = false
    private var runningBufferMs = 0
    private var restarting = false
    private var adaptTask: Task<Void, Never>?
    private var effectiveBufferMs: Int {
        phoneLocked && bigBufferWhenLocked ? max(bufferMs, Self.lockedBufferMs) : bufferMs
    }

    private var knownHosts: [String] {
        get { UserDefaults.standard.stringArray(forKey: "knownHosts") ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(8)), forKey: "knownHosts") }
    }

    init() {
        let d = UserDefaults.standard
        bufferMs = d.object(forKey: "bufferMs") as? Int ?? 40
        suggest = d.object(forKey: "suggest") as? Bool ?? true
        bigBufferWhenLocked = d.object(forKey: "bigBufferWhenLocked") as? Bool ?? true
        shakeToSwitch = d.object(forKey: "shakeToSwitch") as? Bool ?? true
    }

    // MARK: lifecycle

    func start() {
        adb = Shell.locate("adb")
        scrcpy = Shell.locate("scrcpy")
        if adb == nil { problem = "adb not found. Install Android platform-tools." }
        else if scrcpy == nil { problem = "scrcpy not found. Run: brew install scrcpy" }

        server = ControlServer { [weak self] cmd in
            await self?.handle(command: cmd) ?? "off"
        }
        server?.start()

        loop = Task { [weak self] in
            if let adb = self?.adb { _ = await Shell.run(adb, ["start-server"], timeout: 10) }
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func shutdown() {
        loop?.cancel()
        stream?.terminate()
        stream = nil
        // Blocking on purpose: the app is about to exit.
        if let adb, let phone {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: adb)
            p.arguments = ["-s", phone.serial, "shell", Self.killHelpers
                           + "; am stopservice -n dev.earshot/.KeepAwakeService"
                           + "; am stopservice -n dev.earshot/.ShakeService"
                           + "; am broadcast -n dev.earshot/.StateReceiver -a dev.earshot.STATE --ez on false"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            if (try? p.run()) != nil {
                let deadline = Date().addingTimeInterval(3)
                while p.isRunning, Date() < deadline { usleep(50_000) }
                if p.isRunning { p.terminate() }
            }
        }
    }

    /// The [r] keeps the pattern from matching the shell that runs it.
    private static let killHelpers = "pkill -f 'com.genymobile.scrcpy.Serve[r]'"

    private func removeLeftoverHelpers() async {
        guard let adb, let phone else { return }
        _ = await Shell.run(adb, ["-s", phone.serial, "shell", Self.killHelpers], timeout: 5)
    }

    // MARK: commands (menu and phone tile)

    func handle(command: String) async -> String {
        switch command {
        case "toggle": streaming ? stopStream() : await startStream()
        case "start": if !streaming { await startStream() }
        case "stop": stopStream()
        case "locked": screenChanged(locked: true)
        case "unlocked": screenChanged(locked: false)
        default: break
        }
        if phone == nil { return "nophone" }
        return streaming ? "on" : "off"
    }

    func toggle() {
        Task { _ = await handle(command: "toggle") }
    }

    private func startStream(attempt: Int = 0) async {
        guard let scrcpy, let adb else { return }
        if phone == nil { await refresh() }
        guard let phone else {
            problem = "Phone not found."
            if streaming { streaming = false; lastStop = Date() }
            return
        }

        // Two capture helpers on the phone split the audio between them, which
        // sounds sped-up and crackly. Make sure none is left from an earlier run.
        await removeLeftoverHelpers()
        try? await Task.sleep(nanoseconds: 300_000_000)  // let the old helper finish exiting

        let p = Process()
        p.executableURL = URL(fileURLWithPath: scrcpy)
        p.arguments = ["-s", phone.serial, "--no-window", "--no-control", "--no-power-on", "--audio-codec=raw",
                       "--audio-buffer=\(effectiveBufferMs)"]
        runningBufferMs = effectiveBufferMs
        var env = ProcessInfo.processInfo.environment
        env["ADB"] = adb
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        p.environment = env
        let log = Self.logHandle()
        p.standardOutput = log
        p.standardError = log
        p.standardInput = FileHandle.nullDevice
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in self?.streamEnded(proc) }
        }
        do {
            try p.run()
            stream = p
            streamStarted = Date()
            streamAttempt = attempt
            streaming = true
            problem = nil
            Task { await pushState() }  // don't hold up the reply to the phone's tile
        } catch {
            problem = "Could not start scrcpy: \(error.localizedDescription)"
        }
    }

    private func stopStream() {
        guard stream != nil else { return }
        stopRequested = true
        streaming = false
        stream?.terminate()
    }

    /// The phone app reports screen off / on. Wait a moment before acting so a
    /// quick lock-and-unlock doesn't restart the stream twice.
    private func screenChanged(locked: Bool) {
        phoneLocked = locked
        adaptTask?.cancel()
        adaptTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.adaptBufferToScreenState()
        }
    }

    /// Restarts the stream with the buffer that suits the phone's screen state.
    /// For the second or so this takes, the sound comes from the phone itself.
    private func adaptBufferToScreenState() async {
        guard !restarting else { return }
        restarting = true
        defer { restarting = false }
        var rounds = 0
        while streaming, let old = stream, runningBufferMs != effectiveBufferMs, rounds < 3 {
            rounds += 1
            stream = nil  // so the old process ending is not treated as "stopped"
            old.terminate()
            for _ in 0..<40 where old.isRunning { try? await Task.sleep(nanoseconds: 50_000_000) }
            await startStream()
            // Give it time to prove it is up (or be retried) before judging again.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
        }
    }

    private func setPhoneMediaVolume(_ value: Int) async {
        guard let adb, let phone else { return }
        _ = await Shell.run(adb, ["-s", phone.serial, "shell", "cmd", "media_session",
                                  "volume", "--stream", "3", "--set", "\(value)"], timeout: 5)
    }

    /// One-off repair for a volume an earlier build may have left turned down.
    private func restoreVolumeIfNeeded() async {
        let saved = UserDefaults.standard.integer(forKey: "volumeToRestore")
        guard saved > 0 else { return }
        await setPhoneMediaVolume(saved)
        UserDefaults.standard.removeObject(forKey: "volumeToRestore")
    }

    private func streamEnded(_ proc: Process) {
        guard proc === stream else { return }
        stream = nil
        // scrcpy sometimes fails to connect to the phone, mostly right after a
        // previous run or while the phone is going to sleep. Try a few times.
        let diedEarly = Date().timeIntervalSince(streamStarted) < 5
        if diedEarly, !stopRequested, streamAttempt < 3, proc.terminationStatus != 0 {
            let next = streamAttempt + 1
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                if stream == nil, streaming { await startStream(attempt: next) }
            }
            return
        }
        if diedEarly, !stopRequested { problem = "Could not start audio. See ~/Library/Logs/Earshot." }
        stopRequested = false
        streaming = false
        phoneLocked = false
        lastStop = Date()
        Task {
            if stream == nil { await removeLeftoverHelpers() }
            await pushState()
        }
    }

    // MARK: adb link

    private func refresh() async {
        guard let adb else { return }
        tick += 1

        var devices = await listDevices()
        for d in devices where d.state == "offline" && Phone(serial: d.serial).isWireless {
            _ = await Shell.run(adb, ["disconnect", d.serial], timeout: 4)
        }
        let ready = { devices.filter { $0.state == "device" && !$0.serial.hasPrefix("emulator-") }
            .map { Phone(serial: $0.serial) } }

        let usb = ready().first { !$0.isWireless }
        if usb == nil { usbSwitchAttempted.removeAll() }

        if ready().first(where: \.isWireless) == nil {
            if let usb {
                await switchToWifi(from: usb)
            } else {
                await tryKnownAddresses(sweep: tick % 10 == 1)
            }
            devices = await listDevices()
        }

        // Prefer wireless so unplugging the cable never interrupts a stream.
        let chosen = ready().first(where: \.isWireless) ?? ready().first
        if chosen != phone {
            // Don't switch link under a running stream.
            if streaming, let phone, ready().contains(phone) { return }
            phone = chosen
            if chosen != nil { await linkEstablished() }
        } else if chosen != nil, tick % 10 == 0 {
            await openReverseTunnel()
        }

        if devices.contains(where: { $0.state == "unauthorized" }) && chosen == nil {
            problem = "Accept the USB debugging prompt on the phone."
        } else if problem?.hasPrefix("Accept") == true || problem == "Phone not found." {
            if chosen != nil { problem = nil }
        }

        if chosen == nil { shakeArmed = false }
        if chosen != nil, suggest || shakeToSwitch || shakeArmed, !streaming, tick % 2 == 0 {
            await checkForMedia()
        }
    }

    private func listDevices() async -> [(serial: String, state: String)] {
        guard let adb else { return [] }
        let r = await Shell.run(adb, ["devices"], timeout: 6)
        return r.out.split(separator: "\n").dropFirst().compactMap { line in
            let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
            guard parts.count >= 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        }
    }

    /// A phone on USB: learn its Wi-Fi address and move adb onto Wi-Fi.
    private func switchToWifi(from usb: Phone) async {
        guard let adb else { return }
        let r = await Shell.run(adb, ["-s", usb.serial, "shell", "ip", "-f", "inet", "addr", "show", "wlan0"])
        var hosts: [String] = []
        if let ip = Self.firstMatch(#"inet (\d+\.\d+\.\d+\.\d+)"#, in: r.out) { hosts.append(ip) }
        if let gw = await defaultGateway() { hosts.append(gw) }

        for host in hosts where await connect(host) { return }
        guard !usbSwitchAttempted.contains(usb.serial) else { return }
        usbSwitchAttempted.insert(usb.serial)
        _ = await Shell.run(adb, ["-s", usb.serial, "tcpip", "\(Self.adbPort)"], timeout: 10)
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        for host in hosts where await connect(host) { return }
    }

    /// No phone visible: try the hotspot gateway, remembered addresses, then a sweep of the subnet.
    private func tryKnownAddresses(sweep: Bool) async {
        var hosts: [String] = []
        if let gw = await defaultGateway() { hosts.append(gw) }
        hosts += knownHosts.filter { !hosts.contains($0) }
        for host in hosts where await connect(host) { return }
        guard sweep else { return }
        for host in await sweepSubnet() where !hosts.contains(host) {
            if await connect(host) { return }
        }
    }

    private func connect(_ host: String) async -> Bool {
        guard let adb, await portOpen(host) else { return false }
        let r = await Shell.run(adb, ["connect", "\(host):\(Self.adbPort)"], timeout: 6)
        guard r.out.contains("connected to") else {
            // The port answers but the adb daemon can't reach it: seen after a network
            // change. Restarting the daemon fixes it. Never do this mid-stream.
            if r.out.contains("No route to host"), !streaming,
               Date().timeIntervalSince(lastDaemonRestart) > 120 {
                lastDaemonRestart = Date()
                _ = await Shell.run(adb, ["kill-server"], timeout: 6)
                _ = await Shell.run(adb, ["start-server"], timeout: 10)
            }
            return false
        }
        knownHosts = [host] + knownHosts.filter { $0 != host }
        return true
    }

    private func portOpen(_ host: String) async -> Bool {
        await Shell.run("/usr/bin/nc", ["-z", "-G", "1", host, "\(Self.adbPort)"], timeout: 3).ok
    }

    private func defaultGateway() async -> String? {
        let r = await Shell.run("/sbin/route", ["-n", "get", "default"], timeout: 3)
        return Self.firstMatch(#"gateway: (\d+\.\d+\.\d+\.\d+)"#, in: r.out)
    }

    /// Looks for anything answering on the adb port in the Mac's /24.
    private func sweepSubnet() async -> [String] {
        var ip: String?
        for iface in ["en0", "en1"] {
            let r = await Shell.run("/usr/sbin/ipconfig", ["getifaddr", iface], timeout: 3)
            let v = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            if r.ok, !v.isEmpty { ip = v; break }
        }
        guard let ip, let dot = ip.lastIndex(of: ".") else { return [] }
        let prefix = String(ip[..<dot])
        guard prefix.hasPrefix("192.168.") || prefix.hasPrefix("10.") || prefix.hasPrefix("172.") else { return [] }
        let script = "seq 1 254 | xargs -P 64 -I{} sh -c "
            + "'nc -z -G 1 \(prefix).{} \(Self.adbPort) >/dev/null 2>&1 && echo \(prefix).{}'"
        let r = await Shell.run("/bin/sh", ["-c", script], timeout: 12)
        return r.out.split(separator: "\n").map(String.init).filter { $0 != ip }
    }

    private func linkEstablished() async {
        if !streaming { await removeLeftoverHelpers() }
        if !restarting { await restoreVolumeIfNeeded() }
        await openReverseTunnel()
        await pushState()
    }

    /// Lets the phone's tile reach this Mac's control port as localhost.
    private func openReverseTunnel() async {
        guard let adb, let phone else { return }
        let port = "tcp:\(ControlServer.port)"
        _ = await Shell.run(adb, ["-s", phone.serial, "reverse", port, port], timeout: 6)
    }

    // MARK: talking to the phone app

    private func broadcast(_ action: String, extras: [String] = []) async {
        guard let adb, let phone else { return }
        _ = await Shell.run(adb, ["-s", phone.serial, "shell", "am", "broadcast",
                                  "--include-stopped-packages",
                                  "-n", "dev.earshot/.StateReceiver",
                                  "-a", action] + extras, timeout: 6)
    }

    private func pushState() async {
        await broadcast("dev.earshot.STATE", extras: ["--ez", "on", streaming ? "true" : "false"])
        if streaming { await armShake(false) }  // the keep-awake service listens while playing
        await setKeepAwake(streaming)
    }

    /// Shake listening on the phone is only on while a shake could do something:
    /// something is playing there, and this Mac is connected and idle.
    private func armShake(_ on: Bool) async {
        guard let adb, let phone, on != shakeArmed else { return }
        shakeArmed = on
        let verb = on ? "start-foreground-service" : "stopservice"
        _ = await Shell.run(adb, ["-s", phone.serial, "shell", "am", verb,
                                  "-n", "dev.earshot/.ShakeService"], timeout: 6)
    }

    /// While playing, the phone app holds the CPU and Wi-Fi awake so locking the
    /// screen doesn't make the stream stutter.
    private func setKeepAwake(_ on: Bool) async {
        guard let adb, let phone else { return }
        var args = ["-s", phone.serial, "shell", "am", on ? "start-foreground-service" : "stopservice",
                    "-n", "dev.earshot/.KeepAwakeService"]
        if on { args += ["--ez", "shake", shakeToSwitch ? "true" : "false"] }
        _ = await Shell.run(adb, args, timeout: 6)
    }

    /// Watches for media playing on the phone: arms shake listening, and when
    /// something starts, asks the phone app to offer "Play on Mac".
    private func checkForMedia() async {
        guard let adb, let phone else { return }
        // Any app's player counts, whether or not it publishes a media session.
        let r = await Shell.run(adb, ["-s", phone.serial, "shell",
            "dumpsys audio | grep -cE 'state:started.*usage=USAGE_(MEDIA|GAME|UNKNOWN)'"], timeout: 6)
        let playing = (Int(r.out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) > 0
        defer { mediaWasPlaying = playing }

        quietPolls = playing ? 0 : quietPolls + 1
        if playing, shakeToSwitch { await armShake(true) }
        // Stay armed through short pauses; stand down after about half a minute of silence.
        if shakeArmed, !shakeToSwitch || quietPolls >= 5 { await armShake(false) }

        guard suggest, playing, !mediaWasPlaying else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSuggestion) > 300, now.timeIntervalSince(lastStop) > 60 else { return }
        lastSuggestion = now
        await broadcast("dev.earshot.SUGGEST")
    }

    // MARK: helpers

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let range = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func logHandle() -> FileHandle {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Earshot")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("scrcpy.log")
        try? FileManager.default.removeItem(at: file)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        return (try? FileHandle(forWritingTo: file)) ?? FileHandle.nullDevice
    }
}
