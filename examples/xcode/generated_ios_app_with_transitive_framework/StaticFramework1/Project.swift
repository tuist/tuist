import ProjectDescription

let project = Project(
    name: "StaticFramework1",
    targets: [
        .target(
            name: "StaticFramework1",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.StaticFramework1",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: [
                .framework(path: "../Framework2/prebuilt/iOS/Framework2.framework"),
            ]
        ),
        .target(
            name: "StaticFramework1Tests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.StaticFramework1Tests",
            infoPlist: .default,
            sources: "Tests/**",
            dependencies: [
                .target(name: "StaticFramework1"),
            ]
        ),
    ]
)
