// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "EthBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "EthBar",
            path: "Sources/EthBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Network"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
    ]
)
