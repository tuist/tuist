import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
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
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .framework(path: "Prebuilt/prebuilt/PrebuiltStaticFramework.framework"),
                .project(target: "A", path: "Modules/A"),
                .project(target: "AppTestsSupport", path: "Modules/AppTestsSupport"),
                .target(name: "App"),
            ]
        ),
    ]
)
