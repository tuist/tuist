import ProjectDescription

let project = Project(
    name: "Feature",
    targets: [
        .target(
            name: "Feature",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("16.0"),
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: [
                .project(target: "SharedUI", path: "../SharedUI"),
            ]
        ),
        .target(
            name: "FeatureTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.app.tests",
            deploymentTargets: .iOS("16.0"),
            infoPlist: .default,
            sources: "Tests/**",
            dependencies: [
                .target(name: "Feature"),
            ]
        ),
    ]
)
