import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.app",
            infoPlist: .default,
            sources: "Sources/App/**",
            dependencies: [
                .target(name: "AppKit"),
                .target(name: "CrashManager"),
            ]
        ),
        .target(
            name: "CrashManager",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.crash-manager",
            infoPlist: .default,
            sources: "Sources/CrashManager/**",
            dependencies: [
                .external(name: "Sentry"),
            ]
        ),
        .target(
            name: "AppKit",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.app.kit",
            infoPlist: .default,
            sources: "Sources/AppKit/**",
            dependencies: [
                .sdk(name: "c++", type: .library, status: .required),
                .external(name: "Alamofire"),
                .external(name: "FirebaseCrashlytics"),
            ]
        ),
        .target(
            name: "AppKitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.app.kit",
            infoPlist: .default,
            sources: "Tests/AppKit/**",
            dependencies: [
                .target(name: "AppKit"),
                .external(name: "Nimble"),
            ]
        ),
        // Uncomment when multi-platform caching is implemented
        // Target(
        //     name: "WatchApp",
        //     destinations: .watchOS,
        //     product: .watch2App,
        //     bundleId: "dev.tuist.app.watchapp",
        //     infoPlist: .extendingDefault(
        //         with: [
        //             "WKCompanionAppBundleIdentifier": "dev.tuist.app",
        //         ]
        //     ),
        //     sources: ["Sources/Watch/App/**"],
        //     dependencies: [
        //         .target(name: "WatchExtension"),
        //     ]
        // ),
        // Target(
        //     name: "WatchExtension",
        //     destinations: .watchOS,
        //     product: .watch2Extension,
        //     bundleId: "dev.tuist.app.watchapp.extension",
        //     sources: ["Sources/Watch/Extension/**"],
        //     dependencies: [
        //         .external(name: "Alamofire"),
        //     ]
        // ),
    ]
)
