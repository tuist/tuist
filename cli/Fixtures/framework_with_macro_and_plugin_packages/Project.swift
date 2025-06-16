import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .package(url: "https://github.com/lukepistrol/SwiftLintPlugin", from: "0.55.0"),
    ],
    targets: [
        .target(
            name: "Framework",
            destinations: [
                .mac,
            ],
            product: .framework,
            bundleId: "io.tuist.Framework",
            sources: ["Sources/**/*"],
            dependencies: [
                .external(name: "Buildable"),
                .external(name: "ComposableArchitecture"),
                .package(product: "SwiftLint", type: .plugin),
            ]
        ),
    ]
)
