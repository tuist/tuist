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
            dependencies: [.target(name: "AppExtension")]
        ),
        .target(
            name: "AppExtension",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "io.tuist.App.AppExtension",
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "$(PRODUCT_NAME)",
                "NSExtension": [
                    "NSExtensionPrincipalClass": "ExtensionViewController",
                ],
            ]),
            sources: ["AppExtension/**"],
            dependencies: []
        ),
        .target(
            name: "AppExtensionTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.App.AppExtensionTests",
            infoPlist: .default,
            sources: ["AppExtensionTests/**"],
            dependencies: [.target(name: "AppExtension")]
        ),
    ]
)
