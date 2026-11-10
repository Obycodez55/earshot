import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = Engine()
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
            Text(engine.streaming ? "Playing phone audio · \(phone.label)" : "Phone connected · \(phone.label)")
        } else {
            Text("Looking for phone…")
        }

        Button(engine.streaming ? "Stop" : "Play Phone Audio Here") { engine.toggle() }
            .disabled(engine.phone == nil && !engine.streaming)
            .keyboardShortcut("p")

        Divider()

        Picker("Buffer", selection: $engine.bufferMs) {
            Text("20 ms (tightest sync, may crackle)").tag(20)
            Text("30 ms").tag(30)
            Text("40 ms (recommended)").tag(40)
            Text("60 ms (weak Wi-Fi)").tag(60)
        }
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
