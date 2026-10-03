import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App Target",
            destinations: [.mac],
            product: .app,
            bundleId: "dev.tuist.App",
            deploymentTargets: .macOS("13.0"),
            infoPlist: .default,
            sources: "App/Sources/**",
            dependencies: [
                .external(name: "LocalLib"),
            ]
        ),
    ]
)
