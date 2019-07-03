import ProjectDescription

let project = Project(name: "Framework1",
                      targets: [
                          Target(name: "Framework1",
                                 platform: .iOS,
                                 product: .framework,
                                 productName: "Framework1",
                                 bundleId: "io.tuist.Framework1",
                                 infoPlist: "Config/Framework1-Info.plist",
                                 sources: "Sources/**",
                                 dependencies: [
                                     .project(target: "Framework2-iOS", path: "../Framework2"),
                          ]),
                          Target(name: "Framework1Tests",
                                 platform: .iOS,
                                 product: .unitTests,
                                 productName: "Framework1Tests",
                                 bundleId: "io.tuist.Framework1Tests",
                                 infoPlist: "Config/Framework1Tests-Info.plist",
                                 sources: "Tests/**",
                                 dependencies: [
                                     .target(name: "Framework1"),
                          ]),
])
