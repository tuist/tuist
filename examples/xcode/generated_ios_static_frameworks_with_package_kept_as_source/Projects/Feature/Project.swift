import ProjectDescription

let project = Project(
    name: "Feature",
    targets: [
        .target(
            name: "Feature",
            destinations: [.iPhone],
            product: .staticFramework,
            bundleId: "dev.tuist.Feature",
            deploymentTargets: .iOS("17.0"),
            sources: ["Sources/**"],
            dependencies: [
                .project(target: "ServicesMockSupport", path: "../ServicesMockSupport"),
            ]
        ),
    ]
)
