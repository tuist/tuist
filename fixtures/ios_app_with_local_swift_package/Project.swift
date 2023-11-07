import ProjectDescription

let project = Project(
    name: "App",
    packages: [
        .package(path: "Packages/PackageA"),
    ],
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "Support/Info.plist",
            sources: ["Sources/**"],
            resources: [
                /* Path to resources can be defined here */
                // "Resources/**"
            ],
            dependencies: [
                .project(target: "FrameworkA", path: "Frameworks/FrameworkA"),
                .package(product: "LibraryA"),
                .package(product: "LibraryB"),
            ]
        ),
        Target(
            name: "AppTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: "Support/Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ]
)
