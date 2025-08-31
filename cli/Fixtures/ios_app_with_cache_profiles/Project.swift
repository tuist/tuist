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
                .target(name: "NonCacheableModule"),
                .target(name: "TaggedModule"),
                .external(name: "Alamofire"),
            ]
        ),
        .target(
            name: "ExpensiveModule",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.ExpensiveModule",
            sources: ["ExpensiveModule/Sources/**"]
        ),
        .target(
            name: "TaggedModule",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.TaggedModule",
            sources: ["TaggedModule/Sources/**"],
            metadata: .metadata(tags: ["cacheable"])
        ),
        .target(
            name: "NonCacheableModule",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.NonCacheableModule",
            sources: ["NonCacheableModule/Sources/**"],
            dependencies: [
                .target(name: "ExpensiveModule"),
            ]
        ),
    ]
)
