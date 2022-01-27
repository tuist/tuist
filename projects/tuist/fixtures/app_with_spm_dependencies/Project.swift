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
                .external(name: "Alamofire"),
                .external(name: "Charts"),
                .external(name: "ComposableArchitecture"),
                .external(name: "FacebookCore"),
                .external(name: "FirebaseAnalytics"),
                .external(name: "FirebaseDatabase"),
                .external(name: "FirebaseFirestore"),
            ]
        ),
    ]
)
