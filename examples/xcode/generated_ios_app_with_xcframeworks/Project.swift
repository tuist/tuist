import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            dependencies: [
                .project(target: "StaticFrameworkA", path: "Modules/StaticFrameworkA"),
                .xcframework(path: "XCFrameworks/MyFramework/prebuilt/MyFramework.xcframework"),
            ],
            settings: .settings(base: [
                "OTHER_LDFLAGS": [
                    "$(inherited)",
                    "-ObjC",
                ],
                "BITCODE_ENABLED": "NO",
            ])
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
