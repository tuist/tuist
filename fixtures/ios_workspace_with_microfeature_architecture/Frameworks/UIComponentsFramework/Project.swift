import BundlePlugin
import ProjectDescription

let project = Project(
    name: "UIComponents",
    targets: [
        .target(
            name: "UIComponents",
            destinations: .iOS,
            product: .framework,
            bundleId: .bundleId(for: "UIComponents"),
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            resources: [
                /* Path to resources can be defined here */
                // "Resources/**"
            ],
            dependencies: [
                /* Target dependencies can be defined here */
                // .framework(path: "Frameworks/MyFramework.framework")
                .project(target: "FeatureContracts", path: "../FeatureContracts"),
            ]
        ),
        .target(
            name: "UIComponentsTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: .bundleId(for: "UIComponentsTests"),
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "UIComponents"),
            ]
        ),
    ]
)
