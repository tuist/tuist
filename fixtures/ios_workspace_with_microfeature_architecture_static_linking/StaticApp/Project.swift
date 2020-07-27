import ProjectDescription

let project = Project(name: "StaticApp",
                      targets: [
                        Target(name: "StaticApp",
                               platform: .iOS,
                               product: .app,
                               bundleId: "io.tuist.App",
                               infoPlist: "Info.plist",
                               sources: ["Sources/**"],
                               resources: [
                                       /* Path to resouces can be defined here */
                                       // "Resources/**"
                               ],
                               dependencies: [
                                    /* Target dependencies can be defined here */
                                    // .framework(path: "Frameworks/MyFramework.framework")
                                    .project(target: "FrameworkA", path: "../Frameworks/FeatureAFramework")
                                ]),
                        Target(name: "StaticAppTests",
                               platform: .iOS,
                               product: .unitTests,
                               bundleId: "io.tuist.AppTests",
                               infoPlist: "Tests.plist",
                               sources: "Tests/**",
                               dependencies: [
                                    .target(name: "StaticApp")
                               ])
                      ])
