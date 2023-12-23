import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        Target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "App/Info.plist",
            sources: ["App/Sources/**"],
            dependencies: [
                .project(target: "SharedDependenciesFramework", path: "SharedDependenciesFramework"),
                .target(name: "AppExtension", condition: .when([.ios])),
            ],
            settings: .settings(base: [
                "OTHER_LDFLAGS": [
                    "$(inherited)",
                    "-ObjC",
                ],
                "BITCODE_ENABLED": "NO",
            ])
        ),
        Target(
            name: "AppExtension",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "io.tuist.App",
            infoPlist: "AppExtension/Info.plist",
            sources: ["AppExtension/Sources/**"],
            dependencies: [
                .project(target: "SharedDependenciesFramework", path: "SharedDependenciesFramework"),
            ],
            settings: .settings(base: [
                "OTHER_LDFLAGS": [
                    "$(inherited)",
                    "-ObjC",
                ],
                "BITCODE_ENABLED": "NO",
            ])
        ),
        Target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: "AppTests/Tests.plist",
            sources: "AppTests/Tests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),

        // MARK: - Frameworks

        Target(
            name: "SharedDependenciesFramework",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.SharedDependenciesFramework",
            infoPlist: .default,
            sources: [], // no sources, it only wraps dependencies to share between executables
            dependencies: [
                .project(target: "DynamicFrameworkA", path: "DynamicFrameworkA"),
                .project(target: "DynamicFrameworkB", path: "DynamicFrameworkB"),
                .xcframework(path: "XCFrameworks/MergeableXCFramework/prebuilt/MergeableXCFramework.xcframework"),
            ],
            mergedBinaryType: .automatic
        ),

        Target(
            name: "DynamicFrameworkA",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.DynamicFrameworkA",
            infoPlist: .default,
            sources: ["DynamicFrameworkA/Sources/**"],
            dependencies: [],
            mergeable: true
        ),

        Target(
            name: "DynamicFrameworkB",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.DynamicFrameworkB",
            infoPlist: .default,
            sources: ["DynamicFrameworkB/Sources/**"],
            dependencies: [],
            mergeable: true
        ),
    ]
)
