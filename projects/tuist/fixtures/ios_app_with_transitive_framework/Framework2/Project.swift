import ProjectDescription

let project = Project(
    name: "Framework2",
    targets: [
        Target(
            name: "Framework2-iOS",
            platform: .iOS,
            product: .framework,
            productName: "Framework2",
            bundleId: "io.tuist.Framework2",
            infoPlist: "Config/Framework2-Info.plist",
            sources: "Sources/**",
            dependencies: [
            ],
            settings: .settings(base: ["BUILD_LIBRARY_FOR_DISTRIBUTION": "YES"])
        ),
        Target(
            name: "Framework2-macOS",
            platform: .macOS,
            product: .framework,
            productName: "Framework2",
            bundleId: "io.tuist.Framework2",
            infoPlist: "Config/Framework2-Info.plist",
            sources: "Sources/**",
            dependencies: [
            ],
            settings: .settings(base: ["BUILD_LIBRARY_FOR_DISTRIBUTION": "YES"])
        ),
    ]
)
