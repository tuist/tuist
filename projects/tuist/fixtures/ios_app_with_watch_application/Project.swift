import ProjectDescription

let project = Project(
    name: "AppWithWatchApp",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
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
            ]
        ),
        // In Xcode 14, watch application can now leverage the `.app` product type
        // rather than the previous `.watch2App` type
        Target(
            name: "WatchApp",
            platform: .watchOS,
            product: .app,
            bundleId: "io.tuist.App.watchkitapp",
            infoPlist: nil,
            sources: "WatchApp/Sources/**",
            resources: "WatchApp/Resources/**",
            dependencies: [
                .target(name: "WatchWidgetExtension"),
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
        Target(
            name: "WatchWidgetExtension",
            platform: .watchOS,
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
            ]
        ),
        Target(
            name: "WatchAppTests",
            platform: .watchOS,
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
