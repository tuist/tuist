import ProjectDescription

let project = Project(name: "App",
                      targets: [
                          Target(name: "App",
                                 platform: .iOS,
                                 product: .app,
                                 bundleId: "io.tuist.App",
                                 infoPlist: "Info.plist",
                                 sources: "Sources/**",
                                 dependencies: [
                                     /* Target dependencies can be defined here */
                                     /* .framework(path: "framework") */
                                 ],
                                 settings: Settings(base: ["CODE_SIGN_IDENTITY": "",
                                                           "CODE_SIGNING_REQUIRED": "NO"])),
                          Target(name: "AppTests",
                                 platform: .iOS,
                                 product: .unitTests,
                                 bundleId: "io.tuist.AppTests",
                                 infoPlist: "Tests.plist",
                                 sources: "Tests/**",
                                 dependencies: [
                                     .target(name: "App"),
                                 ],
                                 settings: Settings(base: ["CODE_SIGN_IDENTITY": "",
                                                           "CODE_SIGNING_REQUIRED": "NO"])),
])
