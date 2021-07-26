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
            sources: "App/**",
            dependencies: [
                .external(name: "Adjust"),
                .external(name: "Alamofire"),
                .external(name: "ComposableArchitecture"),
                .external(name: "FacebookCore"),
                .external(name: "FirebaseAnalytics"),
            ]
        ),
        Target(
            name: "AppTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.appTests",
            infoPlist: .default,
            sources: "AppTests/**",
            dependencies: [
                .target(name: "App"),
                .external(name: "Quick"),
                .external(name: "Nimble"),
            ]
        ),
    ]
)
