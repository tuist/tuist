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
        // Archiving is the only action that tells `TARGET_BUILD_DIR` and `BUILT_PRODUCTS_DIR`
        // apart for this target: `SKIP_INSTALL=YES` moves the former to `UninstalledProducts/`
        // while `ProcessXCFramework` leaves the extracted slice in the latter. Generated settings
        // that point at the slice have to survive that split.
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
