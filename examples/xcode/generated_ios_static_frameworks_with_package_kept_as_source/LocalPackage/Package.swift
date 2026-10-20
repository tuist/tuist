// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalPackage",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Analytics", targets: ["Analytics"]),
    ],
    targets: [
        .target(
            name: "CrashReporting",
            publicHeadersPath: "include"
        ),
        .target(
            name: "Analytics",
            dependencies: ["CrashReporting"]
        ),
    ]
)
