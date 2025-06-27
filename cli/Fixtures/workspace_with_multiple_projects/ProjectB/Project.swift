import ProjectDescription

let project = Project(
    name: "ProjectB",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            infoPlist: .default,
            sources: ["Targets/App/Tests/**"],
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ]
)
