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

let project = Project(
    name: "Framework1",
    settings: settings,
    targets: [
        .target(
            name: "Framework1",
            destinations: .iOS,
            product: .framework,
            productName: "Framework1",
            bundleId: "io.tuist.Framework1",
            infoPlist: "Support/Framework1-Info.plist",
            sources: "Sources/**",
            dependencies: [
                .project(target: "Framework2", path: "../Framework2"),
            ]
        ),
        .target(
            name: "Framework1Tests",
            destinations: .iOS,
            product: .unitTests,
            productName: "Framework1Tests",
            bundleId: "io.tuist.Framework1Tests",
            infoPlist: "Support/Framework1Tests-Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Framework1"),
            ]
        ),
    ]
)
