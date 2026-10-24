// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DataLayerCLI",
    platforms: [.macOS(.v13), .iOS("26.0")],
    products: [
        .executable(name: "overlay", targets: ["DataLayerCLIEntry"]),
        .executable(name: "datalayer-video-worker", targets: ["DataLayerVideoWorker"]),
        .library(name: "OverlayCore", targets: ["OverlayCore"])
    ],
    targets: [
        .target(name: "OverlayCore", dependencies: [
            .target(name: "CCairoRuntime", condition: .when(platforms: [.linux, .windows]))
        ]),
        .target(name: "CCairoRuntime", linkerSettings: [
            .linkedLibrary("dl", .when(platforms: [.linux]))
        ]),
        .target(name: "DataLayerCLICommand", dependencies: ["OverlayCore"], path: "Sources/overlay"),
        .executableTarget(name: "DataLayerCLIEntry", dependencies: ["DataLayerCLICommand"], path: "Sources/OverlayCLIEntry"),
        .executableTarget(name: "DataLayerVideoWorker", dependencies: ["OverlayCore"], path: "Sources/VideoExportWorker"),
        .testTarget(name: "OverlayCoreTests", dependencies: ["OverlayCore"]),
        .testTarget(name: "OverlayCLITests", dependencies: ["DataLayerCLICommand"])
    ]
)
