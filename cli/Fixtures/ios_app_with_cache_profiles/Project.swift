import ProjectDescription

let project = Project(
    name: "CacheProfilesExample",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "com.example.App",
            infoPlist: .default,
            sources: ["App/Sources/**"],
            dependencies: [
                .target(name: "ExpensiveModule"),
            ]
        ),
        .target(
            name: "ExpensiveModule",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.ExpensiveModule",
            sources: ["ExpensiveModule/Sources/**"]
        ),
    ]
)
