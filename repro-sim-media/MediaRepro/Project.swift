import ProjectDescription

let project = Project(
    name: "MediaRepro",
    targets: [
        .target(
            name: "MediaRepro",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MediaRepro",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
                "NSMicrophoneUsageDescription": "Media repro",
                "NSCameraUsageDescription": "Media repro",
            ]),
            sources: ["Sources/**"],
            resources: ["Resources/**"]
        ),
        .target(
            name: "MediaReproUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "dev.tuist.MediaReproUITests",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["UITests/**"],
            dependencies: [.target(name: "MediaRepro")]
        ),
    ]
)
