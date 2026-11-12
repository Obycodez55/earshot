import CoreAudio
import Foundation

/// Pauses and resumes whatever is playing on the Mac itself.
///
/// Finding out *what* is playing is done with Core Audio's public process list
/// (which apps are sending sound to an output right now). macOS no longer lets
/// ordinary apps ask the Now Playing system that question, but it still accepts
/// pause and play commands, which go to whichever app owns Now Playing.
enum MacMedia {
    /// Apps sending sound to an output right now, apart from system sounds,
    /// command-line tools (which includes our own scrcpy) and `excluding`.
    static func appsMakingSound(excluding: Set<pid_t> = []) -> Set<pid_t> {
        var found: Set<pid_t> = []
        for object in processObjects() {
            guard let running: UInt32 = read(object, "piro"), running != 0,
                  let pid: pid_t = read(object, "ppid"), !excluding.contains(pid),
                  pid != getpid() else { continue }
            let bundle = bundleID(object)
            if bundle.isEmpty { continue }
            if bundle.hasPrefix("com.apple."), !appleMediaApps.contains(where: bundle.hasPrefix) { continue }
            found.insert(pid)
        }
        return found
    }

    static func pause() { send(1) }
    static func play() { send(0) }

    // MARK: Core Audio

    private static let appleMediaApps = [
        "com.apple.Music", "com.apple.TV", "com.apple.podcasts", "com.apple.Safari",
        "com.apple.WebKit", "com.apple.QuickTimePlayerX", "com.apple.iBooksX",
    ]

    private static func code(_ s: String) -> UInt32 {
        s.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func address(_ selector: String) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: code(selector),
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObjects() -> [AudioObjectID] {
        var addr = address("prs#")
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func read<T: FixedWidthInteger>(_ object: AudioObjectID, _ selector: String) -> T? {
        var addr = address(selector)
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func bundleID(_ object: AudioObjectID) -> String {
        var addr = address("pbid")
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr,
              let value else { return "" }
        return value.takeRetainedValue() as String
    }

    // MARK: Now Playing commands

    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool

    private static let sendCommand: SendCommand? = {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL),
              let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString)
        else { return nil }
        return unsafeBitCast(pointer, to: SendCommand.self)
    }()

    private static func send(_ command: UInt32) {
        _ = sendCommand?(command, nil)
    }
}
