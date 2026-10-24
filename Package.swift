// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DataLayerCLI",
    platforms: [.macOS(.v13), .iOS("26.0")],
    products: [
        .executable(name: "overlay", targets: ["DataLayerCLICommand"]),
        .executable(name: "datalayer-video-worker", targets: ["DataLayerVideoWorker"]),
        .library(name: "OverlayCore", targets: ["OverlayCore"])
    ],
    targets: [
        .target(name: "OverlayCore"),
        .executableTarget(name: "DataLayerCLICommand", dependencies: ["OverlayCore"], path: "Sources/overlay"),
        .executableTarget(name: "DataLayerVideoWorker", dependencies: ["OverlayCore"], path: "Sources/VideoExportWorker"),
        .testTarget(name: "OverlayCoreTests", dependencies: ["OverlayCore"]),
        .testTarget(name: "OverlayCLITests", dependencies: ["DataLayerCLICommand"])
    ]
)
