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
                .project(target: "SharedDependenciesFramework", path: "Modules/SharedDependenciesFramework"),
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
                .project(target: "SharedDependenciesFramework", path: "Modules/SharedDependenciesFramework"),
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
    ]
)
