import ProjectDescription

let project = Project(name: "FeatureContracts",
                      targets: [
                          Target(name: "FeatureContracts",
                                 platform: .iOS,
                                 product: .framework,
                                 bundleId: "io.tuist.FeatureContracts",
                                 infoPlist: "Info.plist",
                                 sources: ["Sources/**"],
                                 resources: [
                                     /* Path to resouces can be defined here */
                                     // "Resources/**"
                                 ],
                                 dependencies: [
                                     /* Target dependencies can be defined here */
                                     // .framework(path: "Frameworks/MyFramework.framework")
                                     .project(target: "Data", path: "../DataFramework"),
                                     .project(target: "Core", path: "../CoreFramework"),
                                 ]),
                          Target(name: "FeatureContractsTests",
                                 platform: .iOS,
                                 product: .unitTests,
                                 bundleId: "io.tuist.FeatureContractsTests",
                                 infoPlist: "Tests.plist",
                                 sources: "Tests/**",
                                 dependencies: [
                                     .target(name: "FeatureContracts"),
                                 ]),
                      ])
