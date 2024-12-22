import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone, .iPad, .macCatalyst],
            product: .app,
            bundleId: "io.tuist.App",
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
                .external(name: "ResourcesFramework"),
            ]
        ),
        .target(
            name: "App-macOS",
            destinations: .macOS,
            product: .app,
            bundleId: "io.tuist.App",
            sources: ["App/Sources/**"],
            dependencies: [
                .target(name: "MacPlugin"),
                .external(name: "ResourcesFramework"),
            ]
        ),
        .target(
            name: "MacPlugin",
            destinations: .macOS,
            product: .bundle,
            bundleId: "io.tuist.App.MacPlugin"
        ),
    ]
)
