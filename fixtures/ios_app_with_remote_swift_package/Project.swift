import ProjectDescription

let project = Project(
    name: "App",
    packages: [
        .package(url: "https://github.com/ReactiveX/RxSwift", .upToNextMajor(from: "5.0.0")),
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
                .package(product: "RxSwift"),
                .package(product: "RxBlocking"),
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
