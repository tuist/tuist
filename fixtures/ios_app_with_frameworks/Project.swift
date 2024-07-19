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
            bundleId: "io.tuist.App",
            infoPlist: .extendingDefault(with: [:]),
            sources: "App/Sources/**",
            resources: "App/Sources/Main.storyboard",
            dependencies: [
                .target(name: "Framework1"),
                .target(name: "Framework2-iOS"),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: .extendingDefault(with: [:]),
            sources: "App/Tests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
        .target(
            name: "Framework1",
            destinations: .iOS,
            product: .framework,
            productName: "Framework1",
            bundleId: "io.tuist.Framework1",
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
            ]
        ),
        .target(
            name: "Framework1Tests",
            destinations: .iOS,
            product: .unitTests,
            productName: "Framework1Tests",
            bundleId: "io.tuist.Framework1Tests",
            infoPlist: "Framework1/Config/Framework1Tests-Info.plist",
            sources: "Framework1/Tests/**",
            dependencies: [
                .target(name: "Framework1"),
            ]
        ),
        .target(
            name: "Framework2-iOS",
            destinations: .iOS,
            product: .framework,
            productName: "Framework2",
            bundleId: "io.tuist.Framework2",
            infoPlist: "Framework2/Config/Framework2-Info.plist",
            sources: "Framework2/Sources/**",
            headers: .headers(
                public: "Framework2/Sources/Public/**",
                private: "Framework2/Sources/Private/**",
                project: "Framework2/Sources/Project/**"
            ),
            dependencies: [
                .target(name: "Framework3"),
            ]
        ),
        .target(
            name: "Framework2-macOS",
            destinations: [.mac],
            product: .framework,
            productName: "Framework2",
            bundleId: "io.tuist.Framework2",
            infoPlist: "Framework2/Config/Framework2-Info.plist",
            sources: "Framework2/Sources/**",
            headers: .headers(
                public: "Framework2/Sources/Public/**",
                private: "Framework2/Sources/Private/**",
                project: "Framework2/Sources/Project/**"
            ),
            dependencies: []
        ),
        .target(
            name: "Framework2Tests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.Framework2Tests",
            infoPlist: "Framework2/Config/Framework2Tests-Info.plist",
            sources: "Framework2/Tests/**",
            dependencies: [
                .target(name: "Framework2-iOS"),
            ]
        ),
        .target(
            name: "Framework3",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.Framework3",
            infoPlist: "Framework3/Config/Framework3-Info.plist",
            sources: "Framework3/Sources/**",
            dependencies: [
                .target(name: "Framework4"),
            ]
        ),
        .target(
            name: "Framework4",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.Framework4",
            infoPlist: "Framework4/Config/Framework4-Info.plist",
            sources: "Framework4/Sources/**",
            dependencies: [
                .target(name: "Framework5"),
            ]
        ),
        .target(
            name: "Framework5",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.Framework5",
            infoPlist: "Framework5/Config/Framework5-Info.plist",
            sources: "Framework5/Sources/**",
            dependencies: [
                .sdk(name: "ARKit", type: .framework),
            ]
        ),
    ]
)
