import ProjectDescription

let project = Project(
    name: "FrameworkWithSwiftMacro",
    packages: [
        .remote(url: "https://github.com/alschmut/StructBuilderMacro.git", requirement: .exact("0.2.0")),
    ],
    targets: [
        Target(
            name: "Framework",
            platform: .macOS,
            product: .staticLibrary,
            bundleId: "io.tuist.FrameworkWithSwiftMacro",
            sources: ["Sources/**/*"],
            dependencies: [
                .packageMacro(product: "StructBuilder"),
            ]
        ),
    ]
)