import ProjectDescription

let project = Project(
    name: "Framework1",
    targets: [
        .target(
            name: "Framework1-iOS",
            destinations: .iOS,
            product: .framework,
            productName: "Framework1",
            bundleId: "io.tuist.Framework1",
            infoPlist: "Config/Framework1-Info.plist",
            sources: "Sources/**",
            dependencies: [
                .framework(path: "../Framework2/prebuilt/iOS/Framework2.framework"),
            ]
        ),
        .target(
            name: "Framework1-macOS",
            destinations: [.mac],
            product: .framework,
            productName: "Framework1",
            bundleId: "io.tuist.Framework1",
            infoPlist: "Config/Framework1-Info.plist",
            sources: "Sources/**",
            dependencies: [
                .framework(path: "../Framework2/prebuilt/Mac/Framework2.framework"),
            ]
        ),
        .target(
            name: "Framework1Tests-iOS",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.Framework1Tests",
            infoPlist: "Tests/Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Framework1-iOS"),
            ]
        ),
        .target(
            name: "Framework1Tests-macOS",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "io.tuist.Framework1Tests",
            infoPlist: "Tests/Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Framework1-macOS"),
            ]
        ),
    ]
)
