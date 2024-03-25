import ProjectDescription

let project = Project(
    name: "AppWithWatchApp",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone, .appleVision],
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
                .target(name: "WatchApp", condition: .when([.ios])),
                .target(name: "ModuleA"),
            ]
        ),
        .target(
            name: "WatchApp",
            destinations: [.appleWatch],
            product: .app,
            bundleId: "io.tuist.App.watchkitapp",
            infoPlist: nil,
            sources: "WatchApp/Sources/**",
            resources: "WatchApp/Resources/**",
            dependencies: [
                .target(name: "ModuleA"),
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
            name: "ModuleA",
            destinations: [.iPhone, .appleVision, .appleWatch],
            product: .framework,
            productName: "ModuleA",
            bundleId: "io.tuist.modulea",
            sources: [
                "Modules/ModuleA/Sources/**",
            ],
            dependencies: [
                .external(name: "CasePaths"),
            ]
        ),
    ]
)
