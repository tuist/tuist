import ProjectDescription

let project = Project(name: "App",
                      targets: [
                          Target(name: "App",
                                 platform: .iOS,
                                 product: .app,
                                 bundleId: "io.tuist.app",
                                 infoPlist: "Info.plist",
                                 sources: "App/**",
                                 dependencies: [
                                     .target(name: "Framework"),
                          ]),
                          Target(name: "Framework",
                                 platform: .iOS,
                                 product: .framework,
                                 bundleId: "io.tuist.framework",
                                 infoPlist: "Info.plist",
                                 sources: "Framework/**",
                                 dependencies: [
                          ]),
])
