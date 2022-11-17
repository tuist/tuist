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
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            infoPlist: "App/Info.plist",
            sources: ["App/Sources/**"]
        ),
    ]
)
