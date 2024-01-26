import ProjectDescription

let settings: Settings = .settings(
    base: [
        "PROJECT_BASE": "PROJECT_BASE",
    ],
    configurations: [
        .debug(name: "Debug", xcconfig: "../ConfigurationFiles/Debug.xcconfig"),
        .release(name: "Beta", xcconfig: "../ConfigurationFiles/Beta.xcconfig"),
        .release(name: "Release", xcconfig: "../ConfigurationFiles/Release.xcconfig"),
    ]
)

let betaScheme = .scheme(
    name: "App-Beta",
    shared: true,
    buildAction: .buildAction(targets: ["App"]),
    runAction: .runAction(configuration: "Beta", executable: "App"),
    archiveAction: .archiveAction(configuration: "Beta"),
    profileAction: .profileAction(configuration: "Release", executable: "App"),
    analyzeAction: .analyzeAction(configuration: "Debug")
)

let project = Project(
    name: "MainApp",
    settings: settings,
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "Support/App-Info.plist",
            sources: "Sources/**",
            dependencies: [
                .project(target: "Framework1", path: "../Framework1"),
                .project(target: "Framework2", path: "../Framework2"),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: "Support/AppTests-Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ],
    schemes: [betaScheme]
)
