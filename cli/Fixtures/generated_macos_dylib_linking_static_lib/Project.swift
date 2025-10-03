import ProjectDescription

let project = Project(
    name: "DynamicLibrary",
    targets: [
        .target(
            name: "DynamicLibrary",
            destinations: .macOS,
            product: .dynamicLibrary,
            bundleId: "dev.tuist.DynamicLibrary",
            buildableFolders: [
                .folder("Sources/DynamicLibrary"),
            ],
            dependencies: [
                .target(name: "StaticLibrary"),
            ]
        ),
        .target(
            name: "StaticLibrary",
            destinations: .macOS,
            product: .dynamicLibrary,
            bundleId: "dev.tuist.StaticLibrary",
            buildableFolders: [
                .folder("Sources/StaticLibrary"),
            ],
            dependencies: []
        ),
    ]
)
