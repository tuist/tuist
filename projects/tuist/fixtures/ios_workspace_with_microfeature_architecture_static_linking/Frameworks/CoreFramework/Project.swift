import ProjectDescription

let project = Project(name: "Core",
                      targets: [
                        Target(name: "Core",
                               platform: .iOS,
                               product: .staticFramework,
                               bundleId: "io.tuist.Core",
                               infoPlist: "Info.plist",
                               sources: ["Sources/**"],
                               resources: [
                                       /* Path to resources can be defined here */
                                       // "Resources/**"
                               ]),
                        Target(name: "CoreTests",
                               platform: .iOS,
                               product: .unitTests,
                               bundleId: "io.tuist.CoreTests",
                               infoPlist: "Tests.plist",
                               sources: "Tests/**",
                               dependencies: [
                                    .target(name: "Core")
                               ])
                      ])
