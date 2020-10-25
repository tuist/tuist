import ProjectDescription

let project = Project(name: "Framework",
                      targets: [
                          Target(name: "Framework",
                                 platform: .iOS,
                                 product: .framework,
                                 bundleId: "io.tuist.Framework",
                                 infoPlist: .default,
                                 sources: "Sources/**"),
                          Target(name: "FrameworkTests",
                                 platform: .iOS,
                                 product: .unitTests,
                                 bundleId: "io.tuist.FrameworkTests",
                                 infoPlist: .default,
                                 sources: "Tests/**",
                                 dependencies: [
                                     .target(name: "Framework"),
                          ])
    ])
