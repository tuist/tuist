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
                .target(name: "DynamicLib"),
            ]
        ),
        .target(
            name: "DynamicLib",
            destinations: [.mac],
            product: .dynamicLibrary,
            bundleId: "com.example.dynamiclib",
            infoPlist: .default,
            sources: "DynamicLib/**"
        ),
    ]
)
