// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VisionBridgeKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "VisionBridgeKit", targets: ["VisionBridgeKit"]),
    ],
    targets: [
        .target(
            name: "VisionBridgeKit",
            path: "Sources/VisionBridgeKit"
        ),
        .testTarget(
            name: "VisionBridgeKitTests",
            dependencies: ["VisionBridgeKit"],
            path: "Tests/VisionBridgeKitTests"
        ),
    ]
)
