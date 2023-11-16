import ProjectDescription

let project = Project(
    name: "FrameworkWithSwiftMacro",
    packages: [
        .remote(url: "https://github.com/alschmut/StructBuilderMacro.git", requirement: .exact("0.2.0")),
    ],
    targets: [
        Target(
            name: "Framework",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.FrameworkWithSwiftMacro",
            sources: ["Sources/**/*"],
            dependencies: [
                .package(product: "StructBuilder", type: .macro),
            ]
        ),
    ]
)
