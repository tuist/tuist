import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.MyApp",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchStoryboardName": "LaunchScreen.storyboard",
                ]
            ),
            sources: ["MyApp/Sources/**"],
            resources: .resources(
                ["MyApp/Resources/**"],
                privacyManifest: .privacyManifest(
                    tracking: false,
                    trackingDomains: [],
                    collectedDataTypes: [
                        [
                            "NSPrivacyCollectedDataType": "NSPrivacyCollectedDataTypeName",
                            "NSPrivacyCollectedDataTypeLinked": false,
                            "NSPrivacyCollectedDataTypeTracking": false,
                            "NSPrivacyCollectedDataTypePurposes": [
                                "NSPrivacyCollectedDataTypePurposeAppFunctionality",
                            ],
                        ],
                    ],
                    accessedApiTypes: [
                        [
                            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                            "NSPrivacyAccessedAPITypeReasons": [
                                "CA92.1",
                            ],
                        ],
                    ]
                )
            ),
            dependencies: []
        ),
        .target(
            name: "MyAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
