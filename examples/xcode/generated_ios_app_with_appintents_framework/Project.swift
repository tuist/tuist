import ProjectDescription

let project = Project(
    name: "AppIntentsApp",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.AppIntentsApp",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: "App/Sources/**",
            dependencies: [
                .target(name: "IntentsFramework"),
            ]
        ),
        .target(
            name: "IntentsFramework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.IntentsFramework",
            deploymentTargets: .iOS("17.0"),
            sources: "IntentsFramework/Sources/**"
        ),
    ]
)
