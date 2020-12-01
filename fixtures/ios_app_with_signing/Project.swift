import ProjectDescription

let configurations: [CustomConfiguration] = [
    .debug(name: "Debug", xcconfig: "ConfigurationFiles/Debug.xcconfig"),
    .release(name: "Release", xcconfig: "ConfigurationFiles/Release.xcconfig"),
]

let settings = Settings(base: [
    "PROJECT_BASE": "PROJECT_BASE",
], configurations: configurations)

let project = Project(name: "SignApp",
                      settings: settings,
                      targets: [
                          Target(name: "SignApp",
                                 platform: .iOS,
                                 product: .app,
                                 bundleId: "$(PRODUCT_BUNDLE_IDENTIFIER)",
                                 infoPlist: "Info.plist",
                                 sources: "App/**",
                                 dependencies: [])
                        ]
)
