import ProjectDescription

let project = Project(name: "UIComponents",
                      targets: [
                        Target(name: "UIComponents",
                               platform: .iOS,
                               product: .framework,
                               bundleId: "io.tuist.UIComponents",
                               infoPlist: "Info.plist",
                               sources: ["Sources/**"],
                               resources: [
                                       /* Path to resouces can be defined here */
                                       // "Resources/**"
                               ],
                               dependencies: [
                                    /* Target dependencies can be defined here */
                                    // .framework(path: "Frameworks/MyFramework.framework")
                                    .project(target: "FeatureContracts", path: "../FeatureContracts")
                                ]),
                        Target(name: "UIComponentsTests",
                               platform: .iOS,
                               product: .unitTests,
                               bundleId: "io.tuist.UIComponentsTests",
                               infoPlist: "Tests.plist",
                               sources: "Tests/**",
                               dependencies: [
                                    .target(name: "UIComponents")
                               ])
                      ])
