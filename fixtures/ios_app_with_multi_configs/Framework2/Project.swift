import ProjectDescription

let configurations: [CustomConfiguration] = [
    .debug(name: "Debug", xcconfig: "../ConfigurationFiles/Debug.xcconfig"),
    .release(name: "Beta", xcconfig: "../ConfigurationFiles/Beta.xcconfig"),
    .release(name: "Release", xcconfig: "../ConfigurationFiles/Release.xcconfig"),
]

let settings = Settings(base: [
    "PROJECT_BASE": "PROJECT_BASE",
], configurations: configurations)

let project = Project(name: "Framework2",
                      settings: settings,
                      targets: [
                          Target(name: "Framework2",
                                 platform: .iOS,
                                 product: .framework,
                                 bundleId: "io.tuist.Framework2",
                                 infoPlist: "Support/Framework2-Info.plist",
                                 sources: "Sources/**",
                                 dependencies: []),
                          Target(name: "Framework2Tests",
                                 platform: .iOS,
                                 product: .unitTests,
                                 bundleId: "io.tuist.Framework2Tests",
                                 infoPlist: "Support/Framework2Tests-Info.plist",
                                 sources: "Tests/**",
                                 dependencies: [
                                     .target(name: "Framework2"),
                          ]),
])
