import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            deploymentTargets: .iOS("14.0"),
            infoPlist: .default,
            sources: "App/Sources/**",
            resources: "App/Resources/**",
            dependencies: [
                .external(name: "Buy"),
                .external(name: "Pay"),
                .external(name: "KSCrash"),
                .sdk(name: "c++", type: .library, status: .required),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.app.tests",
            deploymentTargets: .iOS("14.0"),
            infoPlist: .default,
            sources: "AppTests/**",
            dependencies: [.target(name: "App")]
        ),
    ]
)
