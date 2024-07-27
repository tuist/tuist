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
            resources: ["App/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "AppExtension",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "io.tuist.AppExtension",
            infoPlist: .default,
            sources: ["AppExtension/**"],
            dependencies: []
        ),
        .target(
            name: "AppExtensionTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppExtensionTests",
            infoPlist: .default,
            sources: ["AppExtensionTests/**"],
            dependencies: []
        ),
    ]
)
