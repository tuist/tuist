// swift-tools-version: 5.10
@preconcurrency import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams", .upToNextMajor(from: "5.0.6")),
    ]
)
