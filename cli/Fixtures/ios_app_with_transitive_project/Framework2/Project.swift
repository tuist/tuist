import ProjectDescription

let project = Project(
    name: "Framework2",
    targets: [
        .target(
            name: "Framework2-iOS",
            destinations: .iOS,
            product: .staticFramework,
            productName: "Framework2",
            bundleId: "io.tuist.Framework2",
            infoPlist: "Config/Framework2-Info.plist",
            sources: "Sources/**",
            dependencies: [
            ]
        ),
        .target(
            name: "Framework2-macOS",
            destinations: [.mac],
            product: .framework,
            productName: "Framework2",
            bundleId: "io.tuist.Framework2",
            infoPlist: "Config/Framework2-Info.plist",
            sources: "Sources/**",
            dependencies: [
            ]
        ),
    ]
)
