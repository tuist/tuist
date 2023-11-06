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
        .init(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.app"
        ),
    ]
)
