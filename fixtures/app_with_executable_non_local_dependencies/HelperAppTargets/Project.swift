import ProjectDescription

let project = Project(
    name: "HelperAppTargets",
    targets: [
        .target(
            name: "TestHost",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: .default,
            sources: ["Targets/TestHost/**"],
            resources: []
        ),
        .target(
            name: "AppExtension",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "io.tuist.app.extension",
            infoPlist: "Targets/AppExtension/Info.plist",
            sources: "Targets/AppExtension/**"
        ),
    ]
)
