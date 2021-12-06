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
            sources: "CommandLineTool/**",
            dependencies: [
                .target(name: "StaticLib"),
            ]
        ),
        Target(
            name: "StaticLib",
            platform: .macOS,
            product: .staticLibrary,
            bundleId: "com.example.staticlib",
            infoPlist: .default,
            sources: "StaticLib/**"
        ),
    ]
)
