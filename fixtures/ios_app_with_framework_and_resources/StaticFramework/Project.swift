import ProjectDescription

let project = Project(name: "StaticFramework",
                      targets: [
                          Target(name: "StaticFramework",
                                 platform: .iOS,
                                 product: .staticFramework,
                                 bundleId: "io.tuist.StaticFramework",
                                 infoPlist: "Config/StaticFramework-Info.plist",
                                 sources: "Sources/**",
                                 dependencies: []),
                          Target(name: "StaticFrameworkResources",
                                 platform: .iOS,
                                 product: .bundle,
                                 bundleId: "io.tuist.StaticFrameworkResources",
                                 infoPlist: "Config/StaticFrameworkResources-Info.plist",
                                 sources: [],
                                 resources: "Resources/**",
                                 dependencies: []),
])