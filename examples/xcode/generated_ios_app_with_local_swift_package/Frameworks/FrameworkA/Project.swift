import ProjectDescription

let project = Project(
    name: "FrameworkA",
    packages: [
        .package(path: "../../Packages/PackageA"),
    ],
    targets: [
        .target(
            name: "FrameworkA",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.FrameworkA",
            infoPlist: "Config/FrameworkA-Info.plist",
            sources: "Sources/**",
            dependencies: [
                .package(product: "LibraryA"),
            ]
        ),
    ]
)
