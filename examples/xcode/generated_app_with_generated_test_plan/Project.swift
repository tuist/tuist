import ProjectDescription

let project = Project(
    name: "App",
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
            dependencies: [.target(name: "App")]
        ),
        .target(
            name: "AppSnapshotTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppSnapshotTests",
            infoPlist: .default,
            sources: ["Targets/App/SnapshotTests/**"],
            dependencies: [.target(name: "App")]
        ),
    ],
    schemes: [
        .scheme(
            name: "App",
            buildAction: .buildAction(targets: ["App"]),
            testAction: .testPlans([
                .generated(
                    name: "UnitTests",
                    testTargets: [.testableTarget(target: "AppTests")]
                ),
                .generated(
                    name: "SnapshotTests",
                    testTargets: [.testableTarget(target: "AppSnapshotTests")]
                ),
            ]),
            runAction: .runAction(configuration: .debug, executable: "App")
        ),
    ]
)
