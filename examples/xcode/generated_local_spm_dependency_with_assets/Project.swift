import ProjectDescription

let project = Project(
    name: "TuistSampleProject",
    packages: [
        .package(path: "Packages/LocalAssets"),
    ],
    targets: [
        .target(
            name: "TuistSampleProject",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.sample",
            infoPlist: .default,
            sources: ["Sources/**"],
            dependencies: [
                .package(product: "LocalAssets"),
            ]
        ),
    ]
)
