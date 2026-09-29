// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BreakGuard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BreakGuard",
            path: "Sources/BreakGuard"
        )
    ]
)
