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
            sources: ["App/Sources/**"],
            resources: [],
            dependencies: [
                .target(name: "DynamicFrameworkA"),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            infoPlist: .default,
            sources: ["App/Tests/**"],
            resources: [],
            dependencies: [.target(name: "App")]
        ),
        .target(
            name: "DynamicFrameworkA",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.DynamicFrameworkA",
            sources: ["DynamicFrameworkA/**"],
            dependencies: [
                .external(name: "GoogleMobileAds"),
                .target(name: "DynamicFrameworkB"),
            ]
        ),
        .target(
            name: "DynamicFrameworkB",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.DynamicFrameworkB",
            sources: ["DynamicFrameworkB/**"],
            dependencies: [
                .external(name: "CasePaths"),
            ]
        ),
    ]
)
