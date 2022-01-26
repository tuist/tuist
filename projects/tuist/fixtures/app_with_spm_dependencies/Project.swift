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
                .sdk(name: "c++", type: .library, status: .required),
                .external(name: "Adjust"),
                .external(name: "Alamofire"),
                .external(name: "Charts"),
                .external(name: "ComposableArchitecture"),
                .external(name: "CrashReporter"),
                .external(name: "FacebookCore"),
                .external(name: "FirebaseAnalytics"),
                .external(name: "FirebaseDatabase"),
                .external(name: "FirebaseFirestore"),
                .external(name: "GoogleSignIn"),
                .external(name: "Realm"),
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
