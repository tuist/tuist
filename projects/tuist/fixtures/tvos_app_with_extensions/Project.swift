import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        Target(
            name: "App",
            platform: .tvOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "TopShelfExtension"),
            ]
        ),
        Target(
            name: "TopShelfExtension",
            platform: .tvOS,
            product: .tvTopShelfExtension,
            bundleId: "io.tuist.App.TopShelfExtension",
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "$(PRODUCT_NAME)",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.tv-top-shelf",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).ContentProvider",
                ],
            ]),
            sources: "TopShelfExtension/**",
            dependencies: [
            ]
        ),
        Target(
            name: "StaticFramework",
            platform: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.App.StaticFramework",
            infoPlist: .default,
            sources: "StaticFramework/Sources/**"
        ),
    ]
)
