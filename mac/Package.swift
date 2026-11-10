// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Earshot",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Earshot", path: "Sources/Earshot")
    ]
)
