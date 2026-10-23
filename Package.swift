// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DataLayerCLI",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "overlay", targets: ["overlay"]),
        .executable(name: "datalayer-video-worker", targets: ["VideoExportWorker"]),
        .library(name: "OverlayCore", targets: ["OverlayCore"])
    ],
    targets: [
        .target(name: "OverlayCore"),
        .executableTarget(name: "overlay", dependencies: ["OverlayCore"]),
        .executableTarget(name: "VideoExportWorker", dependencies: ["OverlayCore"]),
        .testTarget(name: "OverlayCoreTests", dependencies: ["OverlayCore"]),
        .testTarget(name: "OverlayCLITests", dependencies: ["overlay"])
    ]
)
