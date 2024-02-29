import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: [.appleTv],
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "TopShelfExtension"),
            ]
        ),
        .target(
            name: "TopShelfExtension",
            destinations: [.appleTv],
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
        .target(
            name: "StaticFramework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.App.StaticFramework",
            infoPlist: .default,
            sources: "StaticFramework/Sources/**"
        ),
    ]
)
