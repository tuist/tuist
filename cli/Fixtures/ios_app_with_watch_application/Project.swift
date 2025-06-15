import ProjectDescription

let project = Project(
    name: "AppWithWatchApp",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: .default,
            sources: [
                "App/Sources/**",
            ],
            resources: [
                "App/Resources/**",
            ],
            dependencies: [
                .target(name: "WatchApp"),
                .target(name: "Framework_a_ios"),
            ]
        ),
        .target(
            name: "Framework_a_ios",
            destinations: .iOS,
            product: .framework,
            productName: "FrameworkA",
            bundleId: "io.tuist.framework.a"
        ),
        .target(
            name: "Framework_a_watchos",
            destinations: [.appleWatch],
            product: .framework,
            productName: "FrameworkA",
            bundleId: "io.tuist.framework.a"
        ),
        // In Xcode 14, watch application can now leverage the `.app` product type
        // rather than the previous `.watch2App` type
        .target(
            name: "WatchApp",
            destinations: [.appleWatch],
            product: .app,
            bundleId: "io.tuist.App.watchkitapp",
            infoPlist: nil,
            sources: "WatchApp/Sources/**",
            resources: "WatchApp/Resources/**",
            dependencies: [
                .target(name: "WatchWidgetExtension"),
                .target(name: "Framework_a_watchos"),
            ],
            settings: .settings(
                base: [
                    "GENERATE_INFOPLIST_FILE": true,
                    "CURRENT_PROJECT_VERSION": "1.0",
                    "MARKETING_VERSION": "1.0",
                    "INFOPLIST_KEY_UISupportedInterfaceOrientations": [
                        "UIInterfaceOrientationPortrait",
                        "UIInterfaceOrientationPortraitUpsideDown",
                    ],
                    "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": "io.tuist.App",
                    "INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp": false,
                ]
            )
        ),
        .target(
            name: "WatchWidgetExtension",
            destinations: [.appleWatch],
            product: .appExtension,
            bundleId: "io.tuist.App.watchkitapp.widgetExtension",
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "$(PRODUCT_NAME)",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
                ],
            ]),
            sources: "WatchWidgetExtension/Sources/**",
            resources: "WatchWidgetExtension/Resources/**",
            dependencies: [
                .target(name: "Framework_a_watchos"),
            ]
        ),
        .target(
            name: "WatchAppTests",
            destinations: [.appleWatch],
            product: .unitTests,
            bundleId: "io.tuist.App.watchkitapptests",
            infoPlist: .default,
            sources: "WatchApp/Tests/**",
            dependencies: [
                .target(name: "WatchApp"),
            ]
        ),
    ]
)
