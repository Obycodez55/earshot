import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = Engine()
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Used by install.sh, so installing also sets the app to open at login.
        if CommandLine.arguments.contains("--enable-login-item"),
           SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
        // Being killed (not just quit from the menu) must still stop the stream,
        // or the capture helper is left running on the phone.
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.engine.shutdown()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
        engine.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.shutdown()
    }
}

@main
struct EarshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(engine: delegate.engine)
        } label: {
            MenuBarIcon(engine: delegate.engine)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarIcon: View {
    @ObservedObject var engine: Engine

    var body: some View {
        Image(systemName: engine.streaming ? "ear.fill" : "ear")
    }
}

private struct MenuContent: View {
    @ObservedObject var engine: Engine
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        if let problem = engine.problem {
            Text(problem)
        } else if let phone = engine.phone {
            if engine.streaming {
                Text(engine.mode == .mirror ? "Mirroring phone · \(phone.label)"
                                            : "Playing phone audio · \(phone.label)")
            } else {
                Text("Phone connected · \(phone.label)")
            }
        } else {
            Text("Looking for phone…")
        }

        if engine.streaming {
            Button("Stop") { engine.send("stop") }
                .keyboardShortcut("p")
            if engine.mode == .mirror {
                Button("Switch to Audio Only") { engine.send("audio") }
                Button("Show Mirror Window") { engine.send("mirror") }
                    .keyboardShortcut("m")
            } else {
                Button("Mirror Phone Screen Too") { engine.send("mirror") }
                    .keyboardShortcut("m")
            }
        } else {
            Button("Play Phone Audio Here") { engine.send("start") }
                .disabled(engine.phone == nil)
                .keyboardShortcut("p")
            Button("Mirror Phone Screen") { engine.send("mirror") }
                .disabled(engine.phone == nil)
                .keyboardShortcut("m")
        }

        Divider()

        Picker("Buffer", selection: $engine.bufferMs) {
            Text("20 ms (tightest sync, may crackle)").tag(20)
            Text("30 ms").tag(30)
            Text("40 ms (recommended)").tag(40)
            Text("60 ms (weak Wi-Fi)").tag(60)
        }
        Toggle("Turn Phone Screen Off While Mirroring", isOn: $engine.darkPhoneWhileMirroring)
        Toggle("Pause Mac Media While Phone Plays", isOn: $engine.pauseMacMedia)
        Toggle("Shake Phone to Switch", isOn: $engine.shakeToSwitch)
        Toggle("Smoother Sound While Phone Is Locked", isOn: $engine.bigBufferWhenLocked)
        Toggle("Suggest on Phone When Media Starts", isOn: $engine.suggest)
        Toggle("Open at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

        Divider()
        Button("Quit Earshot") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
