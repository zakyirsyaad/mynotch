// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgentMonitorKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AgentMonitorKit",
            targets: ["AgentMonitorKit"]
        )
    ],
    targets: [
        .target(
            name: "AgentMonitorKit",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "AgentMonitorKitTests",
            dependencies: ["AgentMonitorKit"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
