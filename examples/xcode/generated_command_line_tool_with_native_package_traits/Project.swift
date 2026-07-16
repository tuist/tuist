import ProjectDescription

let project = Project(
    name: "App",
    packages: [
        .package(path: "Package", traits: ["NativeIntegration"]),
    ],
    targets: [
        .target(
            name: "App",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "dev.tuist.native-package-traits",
            sources: ["Sources/**"],
            dependencies: [
                .package(product: "FeaturePackage"),
            ]
        ),
    ]
)
