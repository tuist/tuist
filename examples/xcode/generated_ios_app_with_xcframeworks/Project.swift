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
                .target(name: "DynamicFrameworkLinkingStaticXCFramework"),
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
        // A dynamic framework linking a static xcframework is what makes Tuist generate a
        // `-force_load` flag pointing at the slice `ProcessXCFramework` extracts. The flag has to
        // resolve under `archive`, where `SKIP_INSTALL=YES` moves this target's build directory
        // away from the shared products directory the slice lands in.
        .target(
            name: "DynamicFrameworkLinkingStaticXCFramework",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.DynamicFrameworkLinkingStaticXCFramework",
            sources: ["DynamicFrameworkLinkingStaticXCFramework/**"],
            dependencies: [
                .xcframework(path: "XCFrameworks/MyStaticLibrary/prebuilt/MyStaticLibrary.xcframework"),
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
