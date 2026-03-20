import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            deploymentTargets: .iOS("16.0"),
            sources: "Sources/**",
            dependencies: [
                .project(target: "StaticFramework", path: "../StaticFramework"),
            ]
        ),
    ]
)
