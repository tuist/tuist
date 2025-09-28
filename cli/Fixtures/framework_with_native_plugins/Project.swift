import ProjectDescription

let project = Project(
    name: "MyFramework",
    packages: [
//      .package(url: "https://github.com/lukepistrol/SwiftLintPlugin", from: "0.55.0"),
//      .package(url: "https://github.com/ordo-one/package-benchmark", .upToNextMajor(from: "1.4.0")),
//      .package(url: "https://github.com/YIshihara11201/MySPMPlugin", from: "1.0.1"),
    ],
    targets: [
        .target(
            name: "MyFramework",
            destinations: [.mac],
            product: .framework,
            bundleId: "io.tuist.Framework",
            sources: ["Sources/**/*"],
            dependencies: [
                .external(name: "MySPMPlugin"),
            ]
        ),
    ]
)
