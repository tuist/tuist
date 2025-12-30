import ProjectDescription

let project = Project(
    name: "iOS app with none LinkingStatus framework",
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
            sources: ["App/Sources/**"],
            dependencies: [
                .target(name: "MyFramework", status: .none),
                .target(name: "ThyFramework"),
            ]
        ),
        .target(
            name: "MyFramework",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.MyFramework",
            sources: ["MyFramework/Sources/**"],
            dependencies: []
        ),
        .target(
            name: "ThyFramework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.ThyFramework",
            sources: ["ThyFramework/Sources/**"]
        ),
    ]
)
