import ProjectDescription

let project = Project(
    name: "App",
    packages: [
        .package(path: "Packages/LocalPackage"),
    ],
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: .default,
            sources: ["Sources/**"],
            resources: [],
            dependencies: [
                // MyFramework is a binary target
                .package(product: "MyFramework"),
            ]
        ),
        Target(
            name: "AppTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: .default,
            sources: "Tests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ]
)
