import BundlePlugin
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: .bundleId(for: "App"),
            infoPlist: "App/Info.plist",
            sources: ["App/Sources/**"],
            resources: [
                /* Path to resources can be defined here */
                // "Resources/**"
            ],
            dependencies: [
                /* Target dependencies can be defined here */
                // .framework(path: "Frameworks/MyFramework.framework")
                .project(target: "FrameworkA", path: "Frameworks/FeatureAFramework"),
            ]
        ),
        Target(
            name: "AppTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: .bundleId(for: "AppTests"),
            infoPlist: "App/Tests.plist",
            sources: "App/Tests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ]
)
