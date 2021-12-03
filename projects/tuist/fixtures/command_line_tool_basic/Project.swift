import ProjectDescription

let project = Project(
    name: "CommandLineTool",
    targets: [
        Target(
            name: "CommandLineTool",
            platform: .macOS,
            product: .commandLineTool,
            bundleId: "com.example.commandlinetool",
            infoPlist: .default,
            sources: ["main.swift"]
        ),
    ]
)
