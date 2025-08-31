import ProjectDescription

let project = Project(
    name: "CacheProfilesInvalidDefault",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "com.example.Invalid.App",
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
            bundleId: "com.example.Invalid.ExpensiveModule",
            sources: ["ExpensiveModule/Sources/**"]
        ),
    ]
)
