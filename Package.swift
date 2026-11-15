// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MiniDock", platforms: [.macOS(.v13)], products: [
    .executable(name: "MiniDock", targets: ["MiniDock"])
], targets: [
    .target(name: "ToggleCore"),
    .executableTarget(name: "MiniDock", dependencies: ["ToggleCore"]),
    .testTarget(name: "ToggleCoreTests", dependencies: ["ToggleCore"])
])
