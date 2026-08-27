// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "repro",
    products: [
        .library(name: "ReproCore", targets: ["ReproCore"]),
    ],
    targets: [
        .target(name: "CShim", publicHeadersPath: "include"),
        .target(
            name: "ReproCore",
            dependencies: ["CShim"],
            swiftSettings: [
                .unsafeFlags(["-module-abi-name", "repro"]),
            ]
        ),
    ]
)
