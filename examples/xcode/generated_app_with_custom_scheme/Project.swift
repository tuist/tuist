import ProjectDescription

// MARK: - Targets of the project

let appTarget: Target = .target(
    name: "App",
    destinations: .iOS,
    product: .app,
    bundleId: "dev.tuist.App",
    sources: ["App/**/*.swift"]
)

// MARK: - Schemes of the project

let appScheme: Scheme = .scheme(
    name: "App",
    shared: true,
    hidden: false,
    buildAction: .buildAction(targets: ["App"], findImplicitDependencies: false),
    testAction: nil,
    runAction: .runAction(),
    archiveAction: .archiveAction(configuration: "Production"),
    profileAction: nil,
    analyzeAction: nil
)

// MARK: - Project

let project = Project(
    name: "App",
    organizationName: "Tuist",
    targets: [
        appTarget,
    ],
    schemes: [appScheme]
)
