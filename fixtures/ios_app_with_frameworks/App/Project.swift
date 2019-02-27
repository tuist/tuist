import ProjectDescription

let project = Project(name: "MainApp",
                      targets: [
                          Target(name: "App",
                                 platform: .iOS,
                                 product: .app,
                                 bundleId: "io.tuist.App",
                                 infoPlist: "Config/App-Info.plist",
                                 sources: "Sources/**",
                                 dependencies: [
                                     .project(target: "Framework1", path: "../Framework1"),
                                     .project(target: "Framework2", path: "../Framework2"),
                          ]),
                          Target(name: "AppTests",
                                 platform: .iOS,
                                 product: .unitTests,
                                 bundleId: "io.tuist.AppTests",
                                 infoPlist: "Config/AppTests-Info.plist",
                                 sources: "Tests/**",
                                 dependencies: [
                                     .target(name: "App"),
                          ]),
])
