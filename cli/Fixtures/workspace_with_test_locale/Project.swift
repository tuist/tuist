import ProjectDescription

let project = Project(
    name: "App",
    options: .options(
        automaticSchemesOptions: .enabled(
            testLanguage: "en",
            testRegion: "US",
            runLanguage: "en",
            runRegion: "US"
        )
    ),
    targets: [
        Target.target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.app"
        ),
    ]
)
