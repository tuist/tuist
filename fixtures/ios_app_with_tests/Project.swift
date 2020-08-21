import ProjectDescription

let project = Project(name: "App",
                      targets: [
                          Target(name: "App",
                                 platform: .iOS,
                                 product: .app,
                                 bundleId: "io.tuist.App",
                                 infoPlist: .file(path: .relativeToManifest("Info.plist")),
                                 sources: .paths([.relativeToManifest("Sources/**")]),
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
                          Target(name: "AppUITests",
                                 platform: .iOS,
                                 product: .uiTests,
                                 bundleId: "io.tuist.AppUITests",
                                 infoPlist: "Tests.plist",
                                 sources: "UITests/**",
                                 dependencies: [
                                    .target(name: "App"),
                                    ]),


                         Target(name: "App-dash",
                                 platform: .iOS,
                                 product: .app,
                                 bundleId: "io.tuist.AppDash",
                                 infoPlist: "Info.plist",
                                 sources: .paths([.relativeToManifest("Sources/**")]),
                                 dependencies: [
                                     /* Target dependencies can be defined here */
                                     /* .framework(path: "framework") */
                                 ],
                                 settings: Settings(base: ["CODE_SIGN_IDENTITY": "",
                                                           "CODE_SIGNING_REQUIRED": "NO"])),
                        Target(name: "App-dashUITests",
                                 platform: .iOS,
                                 product: .uiTests,
                                 bundleId: "io.tuist.AppDashUITests",
                                 infoPlist: "Tests.plist",
                                 sources: "UITests/**",
                                 dependencies: [
                                    .target(name: "App-dash"),
                                    ]),
])
