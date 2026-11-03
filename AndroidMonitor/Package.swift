// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AndroidMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AndroidMonitorCore", targets: ["AndroidMonitorCore"])
    ],
    targets: [
        .target(name: "AndroidMonitorCore"),
        .testTarget(
            name: "AndroidMonitorCoreTests",
            dependencies: ["AndroidMonitorCore"],
            path: "Tests/AndroidMonitorTests"
        )
    ]
)

