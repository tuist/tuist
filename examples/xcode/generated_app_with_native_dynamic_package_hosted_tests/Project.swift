import ProjectDescription

let project = Project(
    name: "HostedPackages",
    packages: [.local(path: "LocalPackage")],
    settings: .settings(base: [
        "MACOSX_DEPLOYMENT_TARGET": "14.0",
        "OTHER_LDFLAGS": ["$(inherited)", "-ObjC"],
    ]),
    targets: [
        .target(
            name: "Feature",
            destinations: [.mac],
            product: .staticFramework,
            bundleId: "dev.tuist.Feature",
            sources: ["Sources/Feature/**"],
            dependencies: [.package(product: "DynamicProduct", type: .runtimeDynamic)]
        ),
        .target(
            name: "HostApp",
            destinations: [.mac],
            product: .app,
            bundleId: "dev.tuist.HostApp",
            infoPlist: .default,
            sources: ["Sources/HostApp/**"],
            dependencies: [
                .target(name: "Feature"),
                .package(product: "DynamicProduct", type: .runtimeDynamicEmbedded),
                .package(product: "StaticProduct"),
                .package(product: "AutomaticProduct"),
                .package(product: "AutomaticDynamicProduct", type: .runtimeDynamic),
            ]
        ),
        .target(
            name: "HostAppTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "dev.tuist.HostAppTests",
            infoPlist: .default,
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "HostApp"),
                .target(name: "Feature"),
                .package(product: "DynamicProduct", type: .runtimeDynamic),
                .package(product: "StaticProduct"),
                .package(product: "AutomaticProduct"),
                .package(product: "AutomaticDynamicProduct", type: .runtimeDynamic),
                .package(product: "TestOnlyProduct"),
            ]
        ),
    ]
)
