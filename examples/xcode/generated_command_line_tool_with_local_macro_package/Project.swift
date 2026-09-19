import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "dev.tuist.local-macro-package",
            sources: ["Sources/**"],
            dependencies: [
                .external(name: "ReproCore"),
            ]
        ),
    ]
)
