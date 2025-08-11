import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.tuist.app-with-buildable-folders",
            infoPlist: .default,
            buildableFolders: [
                .folder(path: "Resources"),
                .folder(path: "Sources"),
            ],
            dependencies: []
        ),
    ]
)
