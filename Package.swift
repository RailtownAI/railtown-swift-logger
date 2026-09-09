// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RailtownLogger",
    platforms: [
        // Floor set by async URLSession.data(for:); Swift Concurrency back-deploys to these.
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "RailtownLogger",
            targets: ["RailtownLogger"]
        ),
    ],
    dependencies: [
        // Same logging stack as RailtracksSwift; the host app picks the backend
        // with LoggingSystem.bootstrap.
        .package(url: "https://github.com/apple/swift-log.git", from: "1.10.1"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "RailtownLogger",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "RailtownLoggerTests",
            dependencies: ["RailtownLogger"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
