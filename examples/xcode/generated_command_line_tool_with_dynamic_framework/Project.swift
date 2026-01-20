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
            sources: "CommandLineTool/**",
            dependencies: [
                .target(name: "DynamicFramework"),
            ]
        ),
        .target(
            name: "DynamicFramework",
            destinations: [.mac],
            product: .framework,
            bundleId: "com.example.dynamicframework",
            infoPlist: .default,
            sources: "DynamicFramework/**"
        ),
    ]
)
