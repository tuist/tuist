import ProjectDescription

let project = Project(
    name: "FrameworkA",
    packages: [
        .package(path: "../../Packages/PackageA"),
    ],
    targets: [
        Target(
            name: "FrameworkA",
            platform: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.FrameworkA",
            infoPlist: "Config/FrameworkA-Info.plist",
            sources: "Sources/**",
            dependencies: [
                .package(product: "LibraryA"),
            ]
        ),
    ]
)
