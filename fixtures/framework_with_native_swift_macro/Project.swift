import ProjectDescription

let project = Project(
    name: "FrameworkWithSwiftMacro",
    targets: [
        Target(
            name: "Framework",
            platform: .iOS,
            product: .staticLibrary,
            bundleId: "io.tuist.FrameworkWithSwiftMacro",
            sources: ["Sources/**/*"],
            dependencies: [
                .external(name: "ComposableArchitecture"),
                .external(name: "CasePaths"),
                .external(name: "StructBuilder"),
            ]
        ),
    ]
)
