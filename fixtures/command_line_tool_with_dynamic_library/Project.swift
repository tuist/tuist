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
                .target(name: "DynamicLib"),
            ]
        ),
        Target(
            name: "DynamicLib",
            destinations: [.mac],
            product: .dynamicLibrary,
            bundleId: "com.example.dynamiclib",
            infoPlist: .default,
            sources: "DynamicLib/**"
        ),
    ]
)
