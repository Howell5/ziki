// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Sotto",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SottoCore", targets: ["SottoCore"]),
        .library(name: "SottoAppCore", targets: ["SottoAppCore"]),
        .executable(name: "Sotto", targets: ["Sotto"]),
        .executable(name: "SottoCoreTestHarness", targets: ["SottoCoreTestHarness"]),
        .executable(name: "SottoAppTestHarness", targets: ["SottoAppTestHarness"])
    ],
    targets: [
        .target(name: "SottoCore"),
        .target(
            name: "SottoAppCore",
            dependencies: ["SottoCore"]
        ),
        .executableTarget(
            name: "Sotto",
            dependencies: ["SottoCore", "SottoAppCore"]
        ),
        .executableTarget(
            name: "SottoCoreTestHarness",
            dependencies: ["SottoCore"],
            path: "Tests/SottoCoreTestHarness"
        ),
        .executableTarget(
            name: "SottoAppTestHarness",
            dependencies: ["SottoAppCore", "SottoCore"],
            path: "Tests/SottoAppTestHarness"
        )
    ]
)
