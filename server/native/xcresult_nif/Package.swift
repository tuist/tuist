// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XCResultNIF",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "XCResultNIF",
            type: .dynamic,
            targets: ["XCResultNIF"]
        ),
        .library(
            name: "XCResultParser",
            targets: ["XCResultParser"]
        ),
    ],
    dependencies: [
        .package(id: "tuist.Path", from: "0.3.8"),
        .package(id: "tuist.FileSystem", .upToNextMajor(from: "0.16.2")),
        // 0.14.4 is the floor, not cosmetic: every release before it waits on the
        // subprocess with a blocking `process.waitUntilExit()` inside the task, so a
        // child that outlives its cancellation parks a Swift cooperative-pool thread
        // for the life of the process. The pool is about as wide as the machine has
        // cores, and this NIF runs one parse per slot, so each parked thread
        // permanently costs the processor a parse slot. Pinned at 0.14.0, production
        // decayed from six concurrent parses to three over a Pod's lifetime.
        // Upstream fix: tuist/Command#249. Kept in step with the root Package.swift.
        .package(id: "tuist.Command", .upToNextMajor(from: "0.14.9")),
        .package(id: "kolos65.Mockable", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "XCResultParser",
            dependencies: [
                .product(name: "Path", package: "tuist.Path"),
                .product(name: "FileSystem", package: "tuist.FileSystem"),
                .product(name: "Command", package: "tuist.Command"),
                .product(name: "Mockable", package: "kolos65.Mockable"),
            ],
            swiftSettings: [
                .define("MOCKING", .when(configuration: .debug)),
            ]
        ),
        .target(
            name: "XCResultNIF",
            dependencies: [
                "XCResultParser",
                .product(name: "Path", package: "tuist.Path"),
            ]
        ),
        .testTarget(
            name: "XCResultParserTests",
            dependencies: [
                "XCResultParser",
                .product(name: "Command", package: "tuist.Command"),
            ],
            resources: [.copy("../Fixtures")]
        ),
    ]
)
