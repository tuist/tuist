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
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.app"
        ),
        .init(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.appTests"
        ),
    ]
)
