// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Daylight",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DaylightCore", targets: ["DaylightCore"]),
        .executable(name: "Daylight", targets: ["DaylightApp"]),
        .executable(name: "DaylightProbe", targets: ["DaylightProbe"]),
        .executable(name: "DaylightChecks", targets: ["DaylightChecks"])
    ],
    targets: [
        .target(
            name: "DaylightCore",
            path: "Sources/DaylightCore"
        ),
        .target(
            name: "DaylightMac",
            dependencies: ["DaylightCore"],
            path: "Sources/DaylightMac"
        ),
        .executableTarget(
            name: "DaylightApp",
            dependencies: ["DaylightCore", "DaylightMac"],
            path: "Sources/DaylightApp"
        ),
        .executableTarget(
            name: "DaylightProbe",
            dependencies: ["DaylightCore", "DaylightMac"],
            path: "Sources/DaylightProbe"
        ),
        .executableTarget(
            name: "DaylightChecks",
            dependencies: ["DaylightCore", "DaylightMac"],
            path: "Sources/DaylightChecks"
        )
    ]
)
