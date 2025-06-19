import ProjectDescription

let project = Project(
    name: "FrameworkWithSwiftMacro",
    packages: [
        .remote(url: "https://github.com/alschmut/StructBuilderMacro", requirement: .exact("0.2.0")),
        .remote(url: "https://github.com/pointfreeco/swift-composable-architecture", requirement: .exact("1.4.0")),
    ],
    targets: [
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.FrameworkWithSwiftMacro",
            sources: ["Sources/**/*"],
            dependencies: [
                .package(product: "ComposableArchitecture", type: .macro),
                .package(product: "CasePaths", type: .macro),
                .package(product: "StructBuilder", type: .macro),
            ]
        ),
    ]
)
