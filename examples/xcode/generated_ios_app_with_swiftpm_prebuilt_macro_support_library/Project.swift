import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.prebuilt-macro-support-app",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: "App/Sources/**",
            dependencies: [
                .external(name: "CasePaths"),
                .external(name: "SwiftUINavigation"),
            ]
        ),
    ]
)
