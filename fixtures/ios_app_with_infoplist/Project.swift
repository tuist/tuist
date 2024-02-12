import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            infoPlist: .default,
            sources: ["App/Sources/**"],
            resources: ["App/Resources/**"]
        ),
    ]
)
