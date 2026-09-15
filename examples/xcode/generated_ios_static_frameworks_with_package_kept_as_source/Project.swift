import ProjectDescription

let project = Project(
    name: "App",
    packages: [
        .local(path: "LocalPackage"),
    ],
    targets: [
        .target(
            name: "Services",
            destinations: [.iPhone],
            product: .staticFramework,
            bundleId: "dev.tuist.Services",
            deploymentTargets: .iOS("17.0"),
            sources: ["Sources/Services/**"]
        ),
        .target(
            name: "ServicesMockSupport",
            destinations: [.iPhone],
            product: .staticFramework,
            bundleId: "dev.tuist.ServicesMockSupport",
            deploymentTargets: .iOS("17.0"),
            sources: ["Sources/ServicesMockSupport/**"],
            dependencies: [
                .target(name: "Services"),
                .package(product: "Analytics", condition: .when([.ios])),
            ]
        ),
        .target(
            name: "Feature",
            destinations: [.iPhone],
            product: .staticFramework,
            bundleId: "dev.tuist.Feature",
            deploymentTargets: .iOS("17.0"),
            sources: ["Sources/Feature/**"],
            dependencies: [
                .target(name: "ServicesMockSupport"),
            ]
        ),
    ]
)
