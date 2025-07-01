import ProjectDescription

let project = Project(
    name: "App",
    packages: [
        .package(path: "Packages/LocalPackage"),
    ],
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            infoPlist: .default,
            sources: ["Sources/**"],
            resources: [],
            dependencies: [
                // MyFramework is a binary target
                .package(product: "MyFramework"),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            infoPlist: .default,
            sources: "Tests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ]
)
