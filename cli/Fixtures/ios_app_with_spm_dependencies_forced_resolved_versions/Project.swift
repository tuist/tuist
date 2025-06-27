import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("16.0"),
            infoPlist: .default,
            sources: "App/Sources/**",
            resources: "App/Resources/**",
            dependencies: [
                .external(name: "SnapKit"),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.app.tests",
            deploymentTargets: .iOS("16.0"),
            infoPlist: .default,
            sources: "AppTests/**",
            dependencies: [.target(name: "App")]
        ),
    ]
)
