import ProjectDescription

/// `Library/Generated` and `Assets/Generated` are filled after `tuist generate` (by a build phase script or a tool in
/// a real project), so the declared contents, not the files on disk, decide how the targets are generated.
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
            dependencies: [
                .target(name: "Library"),
                .target(name: "Assets"),
            ]
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
        .target(
            name: "Assets",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "dev.tuist.assets",
            buildableFolders: [
                "Assets/Sources",
                .folder("Assets/Generated", contents: [.resources]),
            ]
        ),
    ]
)
