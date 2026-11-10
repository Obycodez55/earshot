import Foundation

/// Runs command-line tools and returns their output.
/// Output goes to a temp file, not a pipe: `adb` can spawn a long-lived daemon
/// that inherits a pipe and would keep a read blocked forever.
enum Shell {
    struct Result {
        let code: Int32
        let out: String
        var ok: Bool { code == 0 }
    }

    static func run(_ exe: String, _ args: [String], timeout: TimeInterval = 8,
                    env: [String: String]? = nil) async -> Result {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("earshot-\(UUID().uuidString).out")
                FileManager.default.createFile(atPath: tmp.path, contents: nil)
                defer { try? FileManager.default.removeItem(at: tmp) }
                guard let handle = try? FileHandle(forWritingTo: tmp) else {
                    cont.resume(returning: Result(code: -1, out: "cannot create temp file"))
                    return
                }
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                p.standardOutput = handle
                p.standardError = handle
                p.standardInput = FileHandle.nullDevice
                if let env { p.environment = env }
                do { try p.run() } catch {
                    try? handle.close()
                    cont.resume(returning: Result(code: -1, out: "\(error)"))
                    return
                }
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                p.waitUntilExit()
                killer.cancel()
                try? handle.close()
                let data = (try? Data(contentsOf: tmp)) ?? Data()
                cont.resume(returning: Result(code: p.terminationStatus,
                                              out: String(decoding: data, as: UTF8.self)))
            }
        }
    }

    /// Finds a tool in the usual Homebrew / Android SDK places, then via the login shell.
    static func locate(_ name: String) -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/opt/homebrew/share/android-commandlinetools/platform-tools/\(name)",
            "\(home)/Library/Android/sdk/platform-tools/\(name)",
        ]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return hit
        }
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v \(name)"]
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out.hasPrefix("/") ? out : nil
    }
}
