import ProjectDescription

let project = Project(
    name: "App",
    options: .options(
        defaultKnownRegions: ["en-GB", "Base"],
        developmentRegion: "en-GB"
    ),
    targets: [
        Target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            infoPlist: .default,
            sources: ["App/Sources/**"]
        ),
    ]
)
