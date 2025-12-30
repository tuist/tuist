import ProjectDescription

let settings: Settings = .settings(base: [
    "HEADER_SEARCH_PATHS": "path/to/lib/include",
])

let project = Project(
    name: "MainApp",
    settings: settings,
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MainApp",
            deploymentTargets: .iOS("17.0.0"),
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchStoryboardName": "LaunchScreen",
                ]
            ),
            sources: "App/Sources/**",
            resources: "App/Resources/**",
            dependencies: [
                .target(name: "Framework1"),
                .target(name: "Framework2-iOS"),
            ],
            settings: .settings(
                base: [
                    "DEVELOPMENT_TEAM": "U6LC622NKF",
                    "CODE_SIGN_STYLE": "Automatic",
                    "CODE_SIGN_IDENTITY": "Apple Development",
                ]
            ),
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
            dependencies: [
                .target(name: "Framework2-iOS"),
            ],
            metadata: .metadata(tags: ["Framework1", "Frameworks"])
        ),
        .target(
            name: "Framework1Tests",
            destinations: .iOS,
            product: .unitTests,
            productName: "Framework1Tests",
            bundleId: "dev.tuist.Framework1Tests",
            infoPlist: "Framework1/Config/Framework1Tests-Info.plist",
            sources: "Framework1/Tests/**",
            dependencies: [
                .target(name: "Framework1"),
            ],
            metadata: .metadata(tags: ["Framework1", "Frameworks"])
        ),
        .target(
            name: "Framework2-iOS",
            destinations: .iOS,
            product: .framework,
            productName: "Framework2",
            bundleId: "dev.tuist.Framework2",
            deploymentTargets: .iOS("17.0.0"),
            infoPlist: "Framework2/Config/Framework2-Info.plist",
            sources: "Framework2/Sources/**",
            headers: .headers(
                public: "Framework2/Sources/Public/**",
                private: "Framework2/Sources/Private/**",
                project: "Framework2/Sources/Project/**"
            ),
            dependencies: [
                .target(name: "Framework3"),
                .external(name: "GULNSData"),
            ],
            metadata: .metadata(tags: ["Framework2", "Frameworks"])
        ),
        .target(
            name: "Framework2-macOS",
            destinations: [.mac],
            product: .framework,
            productName: "Framework2",
            bundleId: "dev.tuist.Framework2",
            infoPlist: "Framework2/Config/Framework2-Info.plist",
            sources: "Framework2/Sources/**",
            headers: .headers(
                public: "Framework2/Sources/Public/**",
                private: "Framework2/Sources/Private/**",
                project: "Framework2/Sources/Project/**"
            ),
            dependencies: [],
            metadata: .metadata(tags: ["Framework2", "Frameworks"])
        ),
        .target(
            name: "Framework2Tests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.Framework2Tests",
            infoPlist: "Framework2/Config/Framework2Tests-Info.plist",
            sources: "Framework2/Tests/**",
            dependencies: [
                .target(name: "Framework2-iOS"),
            ],
            metadata: .metadata(tags: ["Framework2", "Frameworks"])
        ),
        .target(
            name: "Framework3",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.Framework3",
            infoPlist: "Framework3/Config/Framework3-Info.plist",
            sources: "Framework3/Sources/**",
            dependencies: [
                .target(name: "Framework4"),
            ],
            metadata: .metadata(tags: ["Framework3", "Frameworks"])
        ),
        .target(
            name: "Framework4",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.Framework4",
            deploymentTargets: .iOS("17.0.0"),
            infoPlist: "Framework4/Config/Framework4-Info.plist",
            sources: "Framework4/Sources/**",
            dependencies: [
                .target(name: "Framework5"),
            ],
            metadata: .metadata(tags: ["Framework4", "Frameworks"])
        ),
        .target(
            name: "Framework5",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.Framework5",
            deploymentTargets: .iOS("17.0.0"),
            infoPlist: "Framework5/Config/Framework5-Info.plist",
            sources: "Framework5/Sources/**",
            dependencies: [
                .sdk(name: "ARKit", type: .framework),
            ],
            metadata: .metadata(tags: ["Framework5", "Frameworks"])
        ),
    ]
)
