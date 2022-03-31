import ProjectDescription

let project = Project(
    name: "App",
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
                .project(target: "FeatureOneFramework", path: .relativeToRoot("Features/FeatureOne")),
            ]
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
                .external(name: "Charts"),
                .external(name: "ComposableArchitecture"),
                .external(name: "FacebookCore"),
                .external(name: "FirebaseAnalytics"),
                .external(name: "FirebaseCrashlytics"),
                .external(name: "FirebaseDatabase"),
                .external(name: "FirebaseFirestore"),
                .external(name: "IterableSDK"),
            ]
        ),
    ]
)
