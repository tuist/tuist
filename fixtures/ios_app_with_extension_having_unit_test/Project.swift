import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App2",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "AppExtension"),
            ]
        ),
        .target(
            name: "AppExtension",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "io.tuist.App2.AppExtension",
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "$(PRODUCT_NAME)",
                "NSExtension": [
                    "NSExtensionMainStoryboard": "MainInterface",
                    "NSExtensionPointIdentifier": "com.apple.message-payload-provider",
                ],
            ]),
            sources: "AppExtension/Sources/**",
            resources: "AppExtension/Resources/**",
            dependencies: [
            ]
        ),
        .target(
            name: "AppExtensionTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: .default,
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "AppExtension"),
            ]
        )
    ]
)
