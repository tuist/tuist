import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "App",
    settings: .projectSettings,
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            infoPlist: .default,
            sources: "Sources/App/**",
            dependencies: [
                .target(name: "AppKit"),
                .project(target: "FeatureOneFramework_iOS", path: .relativeToRoot("Features/FeatureOne")),
                .external(name: "Styles"),
            ],
            settings: .targetSettings
        ),
        Target(
            name: "AppKit",
            platform: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.app.kit",
            infoPlist: .default,
            sources: "Sources/AppKit/**",
            dependencies: [
                .sdk(name: "c++", type: .library, status: .required),
                .external(name: "Alamofire"),
                .external(name: "ComposableArchitecture"),
                .external(name: "FacebookCore"),
                .external(name: "FirebaseAnalytics"),
                .external(name: "FirebaseCrashlytics"),
                .external(name: "FirebaseDatabase"),
                .external(name: "FirebaseFirestore"),
                .external(name: "GRDB"),
                .external(name: "IterableSDK"),
                .external(name: "Stripe"),
                .external(name: "StripeCardScan"),
                .external(name: "TYStatusBarView"),
            ],
            settings: .targetSettings
        ),
        Target(
            name: "WatchApp",
            platform: .watchOS,
            product: .watch2App,
            bundleId: "io.tuist.app.watchapp",
            infoPlist: .extendingDefault(
                with: [
                    "WKCompanionAppBundleIdentifier": "io.tuist.app",
                ]
            ),
            sources: ["Sources/Watch/App/**"],
            dependencies: [
                .target(name: "WatchExtension"),
            ]
        ),
        Target(
            name: "WatchExtension",
            platform: .watchOS,
            product: .watch2Extension,
            bundleId: "io.tuist.app.watchapp.extension",
            sources: ["Sources/Watch/Extension/**"],
            dependencies: [
                .external(name: "Alamofire"),
            ]
        ),
    ],
    schemes: Scheme.allSchemes(for: ["App", "AppKit"], executable: "App")
)
