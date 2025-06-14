import ProjectDescription

let project = Project(
    name: "iOS app with weakly linked framework",
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
            dependencies: [
                .target(name: "MyFramework", status: .optional),
            ]
        ),
        .target(
            name: "MyFramework",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.MyFramework",
            sources: ["MyFramework/Sources/**"],
            dependencies: []
        ),
    ]
)
