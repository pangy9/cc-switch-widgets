// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CCSwitchWidgets",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CCSwitchCore", targets: ["CCSwitchCore"]),
        .executable(name: "CoreChecks", targets: ["CoreChecks"]),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            pkgConfig: "sqlite3"
        ),
        .target(
            name: "CCSwitchCore",
            dependencies: ["CSQLite"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "CoreChecks",
            dependencies: ["CCSwitchCore", "CSQLite"]
        ),
        .testTarget(
            name: "CCSwitchCoreTests",
            dependencies: ["CCSwitchCore"]
        ),
    ]
)
