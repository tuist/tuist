import ProjectDescription

let project = Project(
    name: "Framework2",
    targets: [
        Target(
            name: "Framework2-iOS",
            destinations: .iOS,
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
            destinations: [.mac],
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
