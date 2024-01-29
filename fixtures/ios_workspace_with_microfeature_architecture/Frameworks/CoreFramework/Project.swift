import BundlePlugin
import ProjectDescription

let project = Project(
    name: "Core",
    targets: [
        .target(
            name: "Core",
            destinations: .iOS,
            product: .framework,
            bundleId: .bundleId(for: "Core"),
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            resources: [
                /* Path to resources can be defined here */
                // "Resources/**"
            ]
        ),
        .target(
            name: "CoreTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: .bundleId(for: "CoreTests"),
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Core"),
            ]
        ),
    ]
)
