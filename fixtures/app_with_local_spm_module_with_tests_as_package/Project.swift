import ProjectDescription

let project = Project(
    name: "App",
    packages: [
        .package(path: "LocalSwiftPackage")
    ],
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
                .package(product: "LocalSwiftPackage"),
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
