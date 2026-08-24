import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "dev.tuist.package-access-module-map",
            sources: ["Sources/**"],
            dependencies: [
                .external(name: "ReproCore"),
            ]
        ),
    ]
)
