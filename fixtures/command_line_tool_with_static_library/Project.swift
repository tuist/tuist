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
                .target(name: "StaticLib"),
            ]
        ),
        Target(
            name: "StaticLib",
            destinations: [.mac],
            product: .staticLibrary,
            bundleId: "com.example.staticlib",
            infoPlist: .default,
            sources: "StaticLib/**"
        ),
    ]
)
