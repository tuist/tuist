import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: [.mac],
            product: .commandLineTool,
            bundleId: "dev.tuist.prebuilt-macro-app",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: "App/Sources/**",
            dependencies: [
                .external(name: "MacroDependency"),
            ]
        ),
    ]
)
