import ProjectDescription

let project = Project(
    name: "Framework",
    targets: [
        Target(
            name: Environment.frameworkName.getString(default: "Framework"),
            platform: .macOS,
            product: .framework,
            bundleId: "io.tuist.App",
            infoPlist: .default,
            sources: .paths([.relativeToManifest("Sources/**")])
        ),
    ]
)
