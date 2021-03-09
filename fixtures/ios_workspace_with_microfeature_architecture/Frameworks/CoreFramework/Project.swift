import ProjectDescription
import BundlePlugin

let project = Project(
    name: "Core",
    packages: [
        .package(url: "https://github.com/grpc/grpc-swift.git", .upToNextMajor(from: "1.0.0")),
    ],
    targets: [
        Target(
            name: "Core",
            platform: .iOS,
            product: .framework,
            bundleId: .bundleId(for: "Core"),
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            resources: [
                /* Path to resources can be defined here */
                // "Resources/**"
            ],
            dependencies: [
                .package(product: "GRPC"),
            ]
        ),
        Target(
            name: "CoreTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: .bundleId(for: "CoreTests"),
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Core")
            ]
        )
    ]
)
