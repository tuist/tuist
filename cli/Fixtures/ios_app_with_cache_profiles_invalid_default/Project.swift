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
            sources: ["App/Sources/**"]
        ),
    ]
)
