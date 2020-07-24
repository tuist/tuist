import ProjectDescription

let project = Project(name: "FrameworkA",
                      targets: [
                        Target(name: "FrameworkA",
                               platform: .iOS,
                               product: .framework,
                               bundleId: "io.tuist.FrameworkA",
                               infoPlist: "Info.plist",
                               sources: ["Sources/**"],
                               resources: [
                                       /* Path to resouces can be defined here */
                                       // "Resources/**"
                               ],
                               dependencies: [
                                    /* Target dependencies can be defined here */
                                    // .framework(path: "Frameworks/MyFramework.framework")
                                    .project(target: "FeatureContracts", path: "../FeatureContracts"),
                                    .project(target: "Core", path: "../CoreFramework"),
                                    .project(target: "Data", path: "../DataFramework"),
                                    .project(target: "UIComponents", path: "../UIComponentsFramework")
                                ]),
                        Target(name: "FrameworkATests",
                               platform: .iOS,
                               product: .unitTests,
                               bundleId: "io.tuist.FrameworkATests",
                               infoPlist: "Tests.plist",
                               sources: "Tests/**",
                               dependencies: [
                                    .target(name: "FrameworkA")
                               ])
                      ])
