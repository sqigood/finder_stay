// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FinderSessionRestore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FinderSessionRestore", targets: ["FinderSessionRestoreApp"]),
        .library(name: "FinderSessionRestoreCore", targets: ["FinderSessionRestoreCore"])
    ],
    targets: [
        .target(
            name: "FinderSessionRestoreCore",
            path: "Sources/FinderSessionRestoreCore"
        ),
        .executableTarget(
            name: "FinderSessionRestoreApp",
            dependencies: ["FinderSessionRestoreCore"],
            path: "Sources/FinderSessionRestoreApp"
        ),
        .testTarget(
            name: "FinderSessionRestoreCoreTests",
            dependencies: ["FinderSessionRestoreCore"],
            path: "Tests/FinderSessionRestoreCoreTests"
        )
    ]
)
