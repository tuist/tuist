import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: "Sources/App/**",
            dependencies: [
                .external(name: "SVProgressHUD"),
            ]
        ),
    ]
)
