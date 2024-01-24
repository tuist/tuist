import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        Target(
            name: "App",
            destinations: [.mac],
            product: .app,
            bundleId: "io.tuist.App",
            sources: ["Sources/**/*"],
            dependencies: [
                .external(name: "ComposableArchitecture"),
                .external(name: "CasePaths"),
                .external(name: "StructBuilder"),
            ]
        ),
    ]
)
