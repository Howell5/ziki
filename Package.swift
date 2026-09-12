// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Ziki",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ZikiCore", targets: ["ZikiCore"]),
        .library(name: "ZikiAppCore", targets: ["ZikiAppCore"]),
        .executable(name: "Ziki", targets: ["Ziki"]),
        .executable(name: "ZikiUpdater", targets: ["ZikiUpdater"]),
        .executable(name: "ZikiCoreTestHarness", targets: ["ZikiCoreTestHarness"]),
        .executable(name: "ZikiAppTestHarness", targets: ["ZikiAppTestHarness"])
    ],
    targets: [
        .target(name: "ZikiCore"),
        .target(
            name: "ZikiAppCore",
            dependencies: ["ZikiCore"]
        ),
        .executableTarget(
            name: "Ziki",
            dependencies: ["ZikiCore", "ZikiAppCore"]
        ),
        .executableTarget(name: "ZikiUpdater"),
        .executableTarget(
            name: "ZikiCoreTestHarness",
            dependencies: ["ZikiCore"],
            path: "Tests/ZikiCoreTestHarness"
        ),
        .executableTarget(
            name: "ZikiAppTestHarness",
            dependencies: ["ZikiAppCore", "ZikiCore"],
            path: "Tests/ZikiAppTestHarness"
        )
    ]
)
