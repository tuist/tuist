import ProjectDescription

let project = Project(
    name: "MainApp",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MainApp",
            deploymentTargets: .iOS("17.0.0"),
            sources: "App/Sources/**",
            resources: "App/Resources/**",
            dependencies: [
                .target(name: "Framework1"),
            ],
            metadata: .metadata(tags: ["App"])
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            infoPlist: .extendingDefault(with: [:]),
            sources: "App/Tests/**",
            dependencies: [
                .target(name: "App"),
            ],
            metadata: .metadata(tags: ["App"])
        ),
        .target(
            name: "Framework1",
            destinations: .iOS,
            product: .framework,
            productName: "Framework1",
            bundleId: "dev.tuist.Framework1",
            deploymentTargets: .iOS("17.0.0"),
            infoPlist: .dictionary(
                [
                    "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
                    "CFBundleExecutable": "$(EXECUTABLE_NAME)",
                    "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
                    "CFBundleInfoDictionaryVersion": "6.0",
                    "CFBundleName": "$(PRODUCT_NAME)",
                    "CFBundlePackageType": "APPL",
                    "CFBundleShortVersionString": "1.0",
                    "CFBundleVersion": "1",
                    "LSRequiresIPhoneOS": true,
                    "NSHumanReadableCopyright": "Copyright ©. All rights reserved.",
                    "Test": "Value",
                ]
            ),
            sources: "Framework1/Sources/**",
            dependencies: [],
            metadata: .metadata(tags: ["Framework1", "Frameworks"])
        ),
    ]
)
