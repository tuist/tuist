import ProjectDescription

let project = Project(name: "C",
                      targets: [
                          Target(name: "C",
                                 platform: .iOS,
                                 product: .staticLibrary,
                                 bundleId: "io.tuist.C",
                                 infoPlist: "Info.plist",
                                 sources: "Sources/**",
                                 dependencies: [
                                     /* Target dependencies can be defined here */
                                     /* .framework(path: "framework") */
                          ]),
                          Target(name: "CTests",
                                 platform: .iOS,
                                 product: .unitTests,
                                 bundleId: "io.tuist.BTests",
                                 infoPlist: "Tests.plist",
                                 sources: "Tests/**",
                                 dependencies: [
                                     .target(name: "C"),
                          ]),
])
