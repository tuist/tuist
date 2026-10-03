import ProjectDescription

let project = Project(
    name: "ServicesMockSupport",
    packages: [
        .local(path: "../../LocalPackage"),
    ],
    targets: [
        .target(
            name: "ServicesMockSupport",
            destinations: [.iPhone],
            product: .staticFramework,
            bundleId: "dev.tuist.ServicesMockSupport",
            deploymentTargets: .iOS("17.0"),
            sources: ["Sources/**"],
            dependencies: [
                .project(target: "Services", path: "../Services"),
                .package(product: "Analytics", condition: .when([.ios])),
            ]
        ),
    ]
)
