import ProjectDescription

let project = Project(
    name: "App",
    packages: [
        .local(path: "LocalPackage"),
    ],
    targets: [
        .target(
            name: "PackageLeaf",
            destinations: [.mac],
            product: .staticFramework,
            bundleId: "dev.tuist.PackageLeaf",
            sources: ["Sources/PackageLeaf/**"],
            dependencies: [
                .package(product: "PackageFeature", type: .runtime),
            ]
        ),
        .target(
            name: "FeatureCore",
            destinations: [.mac],
            product: .staticFramework,
            bundleId: "dev.tuist.FeatureCore",
            sources: ["Sources/FeatureCore/**"],
            dependencies: [
                .target(name: "PackageLeaf"),
            ]
        ),
        .target(
            name: "FeatureA",
            destinations: [.mac],
            product: .staticFramework,
            bundleId: "dev.tuist.FeatureA",
            sources: ["Sources/FeatureA/**"],
            dependencies: [
                .target(name: "FeatureCore"),
            ]
        ),
        .target(
            name: "FeatureB",
            destinations: [.mac],
            product: .staticFramework,
            bundleId: "dev.tuist.FeatureB",
            sources: ["Sources/FeatureB/**"],
            dependencies: [
                .package(product: "PackageFeature", type: .runtime),
            ]
        ),
        .target(
            name: "App",
            destinations: [.mac],
            product: .commandLineTool,
            bundleId: "dev.tuist.App",
            sources: ["Sources/App/**"],
            dependencies: [
                .target(name: "FeatureA"),
                .target(name: "FeatureB"),
            ],
            settings: .settings(base: [
                "OTHER_LDFLAGS": ["$(inherited)", "-ObjC"],
            ])
        ),
    ]
)
