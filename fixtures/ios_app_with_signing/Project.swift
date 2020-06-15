import ProjectDescription

let project = Project(name: "SignApp",
                      targets: [
                          Target(name: "SignApp",
                                 platform: .iOS,
                                 product: .app,
                                 bundleId: "io.tuist.SignApp",
                                 infoPlist: "Info.plist",
                                 sources: "App/**",
                                 dependencies: [])
                        ]
)
