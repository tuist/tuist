import ProjectDescription

let project = Project(
    name: "iOSAppWithTransistiveStaticLibraries",
    settings: .settings(
        base: ["SWIFT_ENABLE_EXPLICIT_MODULES": false]
    ),
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            infoPlist: "Info.plist",
            sources: "Sources/**",
            dependencies: [
                .project(target: "A", path: "Modules/A"),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ]
)
