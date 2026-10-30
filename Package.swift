// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MiniToggle", platforms: [.macOS(.v13)], products: [
    .executable(name: "MiniToggle", targets: ["MiniToggle"])
], targets: [
    .target(name: "ToggleCore"),
    .executableTarget(name: "MiniToggle", dependencies: ["ToggleCore"]),
    .testTarget(name: "ToggleCoreTests", dependencies: ["ToggleCore"])
])
