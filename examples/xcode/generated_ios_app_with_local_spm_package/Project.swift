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
            infoPlist: .default,
            sources: "App/Sources/**",
            dependencies: [
                .external(name: "LocalLib"),
            ]
        ),
    ]
)
