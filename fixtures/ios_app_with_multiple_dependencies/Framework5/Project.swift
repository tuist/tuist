import ProjectDescription

let project = Project(name: "Framework5",
                      targets: [
                          Target(name: "Framework5",
                                 platform: .iOS,
                                 product: .framework,
                                 bundleId: "io.tuist.Framework5",
                                 infoPlist: "Config/Framework5-Info.plist",
                                 sources: "Sources/**",
                                 dependencies: []),

                          Target(name: "Framework5Tests",
                                 platform: .iOS,
                                 product: .unitTests,
                                 bundleId: "io.tuist.Framework5Tests",
                                 infoPlist: "Config/Framework5Tests-Info.plist",
                                 sources: "Tests/**",
                                 dependencies: [
                                     .target(name: "Framework5"),
                          ]),
])
