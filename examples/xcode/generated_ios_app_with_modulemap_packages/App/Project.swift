import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.ModuleMapPackages",
            deploymentTargets: .iOS("16.0"),
            sources: "Sources/**",
            dependencies: [
                .external(name: "Gzip"),
                .external(name: "GEOSwift"),
                .external(name: "FirebaseMLModelDownloader"),
            ]
        ),
    ]
)
