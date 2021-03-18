// swift-tools-version:5.2.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TuistBenchmark",
    platforms: [
        .macOS(.v10_13),
    ],
    products: [
        .executable(name: "tuistbench", targets: ["TuistBenchmark"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-tools-support-core", .upToNextMinor(from: "0.2.0")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "TuistBenchmark",
            dependencies: [
                .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
            ]
        ),
    ]
)
