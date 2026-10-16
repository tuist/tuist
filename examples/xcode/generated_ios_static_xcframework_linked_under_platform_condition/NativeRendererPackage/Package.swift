// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NativeRendererPackage",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "NativeRendererKit", targets: ["NativeRendererKit"]),
    ],
    targets: [
        .target(
            name: "NativeRendererKit",
            dependencies: [
                .target(name: "NativeRenderer", condition: .when(platforms: [.iOS])),
            ]
        ),
        .binaryTarget(name: "NativeRenderer", path: "NativeRenderer.xcframework"),
    ]
)
