import ProjectDescription

let project = Project(name: "Project",
                      targets: [
                          Target(name: "App",
                                 platform: .iOS,
                                 product: .app,
                                 bundleId: "io.tuist.App",
                                 infoPlist: "Support/App-Info.plist",
                                 sources: "App/**",
                                 dependencies: [
                                     .sdk(name: "CloudKit.framework", status: .required),
                                     .sdk(name: "ARKit.framework", status: .required),
                                     .sdk(name: "StoreKit.framework", status: .optional),
                                     .sdk(name: "MobileCoreServices.framework", status: .required),
                                     .project(target: "StaticFramework", path: "Modules/StaticFramework")
                          ]),
                          Target(name: "MyTestFramework",
                                 platform: .iOS,
                                 product: .framework,
                                 bundleId: "io.tuist.MyTestFramework",
                                 infoPlist: .default,
                                 sources: "MyTestFramework/**",
                                 dependencies: [
                                     .xctest
                          ]),
                          Target(name: "AppTests",
                                 platform: .iOS,
                                 product: .unitTests,
                                 bundleId: "io.tuist.AppTests",
                                 infoPlist: "Support/Tests.plist",
                                 sources: "Tests/**",
                                 dependencies: [
                                     .target(name: "App"),
                                     .target(name: "MyTestFramework")
                          ]),
                          Target(name: "MacFramework",
                                 platform: .macOS,
                                 product: .framework,
                                 bundleId: "io.tuist.MacFramework",
                                 infoPlist: "Support/Framework-Info.plist",
                                 sources: "Framework/**",
                                 dependencies: [
                                     .sdk(name: "CloudKit.framework", status: .optional),
                                     .sdk(name: "libsqlite3.tbd"),
                          ]),
                          Target(name: "TVFramework",
                                 platform: .tvOS,
                                 product: .framework,
                                 bundleId: "io.tuist.MacFramework",
                                 infoPlist: "Support/Framework-Info.plist",
                                 sources: "Framework/**",
                                 dependencies: [
                                    .sdk(name: "CloudKit.framework", status: .optional),
                                    .sdk(name: "libsqlite3.tbd"),
                            ]),
])
