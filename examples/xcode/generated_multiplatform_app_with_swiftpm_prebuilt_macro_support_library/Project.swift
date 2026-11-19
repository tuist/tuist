import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone, .macCatalyst],
            product: .app,
            bundleId: "dev.tuist.prebuilt-macro-support-library-app",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: "App/Sources/**",
            dependencies: [
                .external(name: "Formatting"),
                .external(name: "Highlighting"),
            ]
        ),
        .target(
            name: "MacCLI",
            destinations: [.mac],
            product: .commandLineTool,
            bundleId: "dev.tuist.prebuilt-macro-support-library-cli",
            deploymentTargets: .macOS("14.0"),
            sources: "MacCLI/Sources/**",
            dependencies: [
                .external(name: "Formatting"),
                .external(name: "Highlighting"),
            ]
        ),
    ]
)
