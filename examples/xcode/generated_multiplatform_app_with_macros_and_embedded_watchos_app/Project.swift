import ProjectDescription

let project = Project(
    name: "AppWithWatchApp",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone, .appleVision],
            product: .app,
            bundleId: "dev.tuist.App",
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
            bundleId: "dev.tuist.App.watchkitapp",
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
                    "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": "dev.tuist.App",
                    "INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp": false,
                ]
            )
        ),
        .target(
            name: "ModuleA",
            destinations: [.iPhone, .appleVision, .appleWatch],
            product: .framework,
            productName: "ModuleA",
            bundleId: "dev.tuist.modulea",
            sources: [
                "Modules/ModuleA/Sources/**",
            ],
            dependencies: [
                .external(name: "CasePaths"),
                .target(name: "ModuleAMacros"),
            ]
        ),
        .target(
            name: "ModuleATests",
            destinations: [.iPhone, .appleVision, .appleWatch],
            product: .unitTests,
            productName: "ModuleATests",
            bundleId: "dev.tuist.moduleatests",
            sources: [
                "Modules/ModuleA/Tests/**",
            ],
            dependencies: [
                .target(name: "ModuleA"),
                .target(name: "ModuleAMacros_Testable"),
                .external(name: "SwiftSyntaxMacrosTestSupport"),
            ]
        ),
        .target(
            name: "ModuleAMacros",
            destinations: .macOS,
            product: .macro,
            productName: "ModuleAMacros",
            bundleId: "dev.tuist.moduleamacros",
            deploymentTargets: .macOS("14.0"),
            sources: [
                "Modules/ModuleA/Macros/Sources/**",
            ],
            dependencies: [
                .external(name: "SwiftSyntaxMacros"),
                .external(name: "SwiftCompilerPlugin"),
            ]
        ),
        .target(
            name: "ModuleAMacros_Testable",
            destinations: [.iPhone, .appleVision, .appleWatch], // Must match platform of the test target
            product: .framework, // Must match be a linkable product
            productName: "ModuleAMacros_Testable",
            bundleId: "dev.tuist.moduleamacros.testable",
            sources: [
                "Modules/ModuleA/Macros/Sources/**",
            ],
            dependencies: [
                .external(name: "SwiftSyntaxMacros"),
                .external(name: "SwiftCompilerPlugin"),
            ]
        ),
    ]
)
