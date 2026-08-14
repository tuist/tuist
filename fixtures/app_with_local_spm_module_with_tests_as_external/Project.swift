import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["App/Sources/**"],
            resources: [],
            dependencies: [
                .external(name: "LocalSwiftPackage"),
            ]
        ),
        .target(
            name: "UnitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.App.Tests",
            sources: ["App/Tests/**"],
            dependencies: [ .target(name: "App")]
        ),
    ],
    schemes: [
        .scheme(
            name: "App",
            shared: true,
            buildAction: .buildAction(targets: ["App"]),
            testAction: .testPlans(
                [.relativeToManifest("App/Tests/TestPlan.xctestplan")]
            ),
            runAction: .runAction(executable: "App")
        ),
    ]
)
