import ProjectDescription

let project = Project(
    name: "CommandLineTool",
    targets: [
        Target(
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
        Target(
            name: "DynamicFramework",
            destinations: [.mac],
            product: .framework,
            bundleId: "com.example.dynamicframework",
            infoPlist: .default,
            sources: "DynamicFramework/**"
        ),
    ]
)
