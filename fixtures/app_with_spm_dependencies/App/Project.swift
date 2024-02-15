import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "App",
    settings: .projectSettings,
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
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
        .target(
            name: "AppKit",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.app.kit",
            infoPlist: .default,
            sources: "Sources/AppKit/**",
            dependencies: [
                .sdk(name: "c++", type: .library, status: .required),
                .external(name: "Alamofire"),
                .external(name: "ComposableArchitecture"),
                .external(name: "ZipArchive"),
                .external(name: "Yams"),
                .external(name: "GoogleSignIn"),
                .external(name: "Sentry"),
                .external(name: "RealmSwift"),
                .external(name: "CocoaLumberjackSwift"),
            ],
            settings: .targetSettings
        ),
        .target(
            name: "WatchApp",
            destinations: [.appleWatch],
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
        .target(
            name: "WatchExtension",
            destinations: [.appleWatch],
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
