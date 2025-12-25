import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone, .iPad, .macCatalyst],
            product: .app,
            bundleId: "dev.tuist.App",
            deploymentTargets: .iOS("16.0"),
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
                .target(name: "MacPlugin", condition: .when([.catalyst])),
                .target(name: "ProjectResourcesFramework"),
                .external(name: "ResourcesFramework"),
            ]
        ),
        .target(
            name: "App-macOS",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.tuist.App",
            sources: ["App/Sources/**"],
            dependencies: [
                .target(name: "MacPlugin"),
                .target(name: "ProjectResourcesFramework"),
                .external(name: "ResourcesFramework"),
            ]
        ),
        .target(
            name: "MacPlugin",
            destinations: .macOS,
            product: .bundle,
            bundleId: "dev.tuist.App.MacPlugin"
        ),
        .target(
            name: "ProjectResourcesFramework",
            destinations: [.iPhone, .iPad, .macCatalyst, .mac],
            product: .staticFramework,
            bundleId: "ProjectResourcesFramework",
            deploymentTargets: .multiplatform(iOS: "13.0", macOS: "11.0"),
            sources: ["ProjectResourcesFramework/Sources/*.swift"],
            resources: ["ProjectResourcesFramework/Sources/greeting.txt"]
        ),
    ]
)
