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
            buildableFolders: [
                "App/Sources",
                "App/Resources",
            ],
            dependencies: [
                .external(name: "Package"),
            ]
        ),
    ]
)
