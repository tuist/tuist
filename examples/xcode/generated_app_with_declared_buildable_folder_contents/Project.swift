import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.tuist.app-with-declared-buildable-folder-contents",
            infoPlist: .default,
            buildableFolders: ["App/Sources"],
            dependencies: [.target(name: "Library")]
        ),
        .target(
            name: "Library",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "dev.tuist.library",
            buildableFolders: [
                .folder("Library/Generated", contents: [.sources, .resources]),
            ]
        ),
    ]
)
