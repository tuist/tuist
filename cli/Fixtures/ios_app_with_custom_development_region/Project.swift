import ProjectDescription

let project = Project(
    name: "App",
    options: .options(
        developmentRegion: "fr"
    ),
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            infoPlist: .default,
            sources: ["App/Sources/**"],
            resources: [
                "App/Resources/**/*.strings",
            ]
        ),
    ]
)
