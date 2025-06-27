import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["Sources/**"],
            dependencies: []
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            infoPlist: .default,
            sources: ["Tests/**"],
            resources: [],
            dependencies: [.target(name: "App")]
        ),
    ],
    schemes: [
        .scheme(
            name: "App",
            testAction: .testPlans(
                [
                    .relativeToManifest("AppTestPlan.xctestplan"),
                ]
            ),
            runAction: .runAction(executable: "App")
        ),
    ]
)
