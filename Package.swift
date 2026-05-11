// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ZuTun",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ZuTun", targets: ["ZuTun"]),
        .executable(name: "ZuTunParserCheck", targets: ["ZuTunParserCheck"])
    ],
    targets: [
        .target(name: "ZuTunCore"),
        .executableTarget(
            name: "ZuTun",
            dependencies: ["ZuTunCore"]
        ),
        .executableTarget(
            name: "ZuTunParserCheck",
            dependencies: ["ZuTunCore"]
        ),
        .testTarget(
            name: "ZuTunCoreTests",
            dependencies: ["ZuTunCore"]
        )
    ]
)
