import ProjectDescription

let featurePackage = Package.package(path: "Package")

let project = Project(
    name: "App",
    packages: [
        featurePackage,
    ],
    packageTraits: [
        featurePackage: ["NativeIntegration"],
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
