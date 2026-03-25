import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.tuist.App",
            infoPlist: .default,
            sources: ["App/Sources/**"],
            dependencies: [
                .external(name: "SelfSignedXCFramework"),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            infoPlist: .default,
            sources: ["App/Tests/**"],
            resources: [],
            dependencies: [.target(name: "App")]
        ),
    ]
)
