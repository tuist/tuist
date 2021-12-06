import ProjectDescription

let settings: Settings = .settings(
    configurations: [
        .debug(name: "Debug", xcconfig: "../ConfigurationFiles/Debug.xcconfig"),
        .release(name: "Beta", xcconfig: "../ConfigurationFiles/Beta.xcconfig"),
        .release(name: "Release", xcconfig: "../ConfigurationFiles/Release.xcconfig"),
    ]
)

// Targets can override select configurations if needed
let targetSettings: Settings = .settings(
    base: [
        "TARGET_BASE": "TARGET_BASE",
    ],
    configurations: [
        .release(name: "Beta", xcconfig: "../ConfigurationFiles/Target.Beta.xcconfig"),
    ]
)

let project = Project(
    name: "Framework2",
    settings: settings,
    targets: [
        Target(
            name: "Framework2",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.Framework2",
            infoPlist: "Support/Framework2-Info.plist",
            sources: "Sources/**",
            dependencies: [],
            settings: targetSettings
        ),
        Target(
            name: "Framework2Tests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.Framework2Tests",
            infoPlist: "Support/Framework2Tests-Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Framework2"),
            ]
        ),
    ]
)
