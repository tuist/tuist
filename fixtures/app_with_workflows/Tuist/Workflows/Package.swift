// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Workflows",
    products: [
        .executable(name: "build", targets: ["Build"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.5.0"))
    ],
    targets: [
        .executableTarget(name: "Build",
                          dependencies: [
                            .product(name: "ArgumentParser", package: "swift-argument-parser")
                          ])
    ]
)
