import ProjectDescription

let project = Project(
    name: "CommandLineTool",
    targets: [
        .target(
            name: "CommandLineTool",
            destinations: [.mac],
            product: .commandLineTool,
            bundleId: "com.example.commandlinetool",
            infoPlist: .default,
            sources: ["main.swift"]
        ),
    ]
)
