import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "Info.plist",
            sources: "Sources/**",
            dependencies: [
                .project(target: "A", path: "Modules/A"),
                .project(target: "C", path: "Modules/C"),
                .framework(path: "Prebuilt/prebuilt/PrebuiltStaticFramework.framework"),
            ]
        ),
        Target(
            name: "AppTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .project(target: "A", path: "Modules/A"),
                .target(name: "App"),
            ]
        ),
    ]
)
