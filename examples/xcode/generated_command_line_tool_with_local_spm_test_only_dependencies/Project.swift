import ProjectDescription

let project = Project(
    name: "CommandLineTool",
    targets: [
        .target(
            name: "CommandLineTool",
            destinations: [.mac],
            product: .commandLineTool,
            bundleId: "dev.tuist.CommandLineTool",
            infoPlist: .default,
            sources: ["main.swift"],
            dependencies: [
                .external(name: "RuntimeLib"),
            ]
        ),
    ]
)
