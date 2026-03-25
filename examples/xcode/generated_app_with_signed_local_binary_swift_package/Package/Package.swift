// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Package",
    platforms: [.macOS("13.0")],
    products: [
        .library(
            name: "SelfSignedXCFramework",
            targets: ["SelfSignedXCFramework"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "SelfSignedXCFramework",
            path: "Binaries/SelfSignedXCFramework.xcframework"
        ),
    ]
)
