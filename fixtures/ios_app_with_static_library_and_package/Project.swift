import ProjectDescription

let project = Project(
    name: "App",
    packages: [
        .package(path: "Packages/PackageA"),
    ],
    targets: [
        Target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "Support/Info.plist",
            sources: ["Sources/**"],
            resources: [
                /* Path to resources can be defined here */
                // "Resources/**"
            ],
            dependencies: [
                .framework(path: "Prebuilt/prebuilt/PrebuiltStaticFramework.framework"),
                .package(product: "LibraryA"),
            ]
        ),
        Target(
            name: "AppTests",
            destinations: .iOS,
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
