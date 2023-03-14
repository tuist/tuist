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
            sources: ["Sources/**"],
            resources: [
                /* Path to resources can be defined here */
                // "Resources/**"
            ],
            dependencies: [
                .target(name: "MyStaticFramework"),
            ],
            settings: .settings(base: [
                "OTHER_LDFLAGS": [
                    "$(inherited)",
                    "-ObjC"
                ]
            ])
        ),
        Target(
            name: "AppTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
        Target(
            name: "MyStaticFramework",
            platform: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.MyStaticFramework",
            infoPlist: "Frameworks/MyStaticFramework/Info.plist",
            sources: ["Frameworks/MyStaticFramework/Sources/**"],
            resources: [
                /* Path to resources can be defined here */
                // "Resources/**"
            ],
            dependencies: [
                .xcframework(path: .relativeToRoot("Frameworks/MyStaticLibrary/prebuilt/MyStaticLibrary.xcframework")),
            ]
        )
    ]
)
