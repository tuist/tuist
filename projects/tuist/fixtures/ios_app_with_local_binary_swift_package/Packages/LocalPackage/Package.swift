// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "LocalPackage",
    platforms: [
        .iOS(.v14),
    ],
    products: [
        .library(
            name: "MyFramework",
            targets: ["MyFramework"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
    ],
    targets: [
        .target(name: "LocalPackage"),
        .binaryTarget(
            name: "MyFramework",
            path: "MyFramework/prebuilt/MyFramework.xcframework"
        ),
    ]
)
