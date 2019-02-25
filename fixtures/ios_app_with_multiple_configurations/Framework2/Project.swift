import ProjectDescription

let targetSettings = Settings(base: [ 
                                   "CONFIG_SOURCE": "Framework2.Project.Base",
                                   "FRAMEWORK2_BASE": "YES",
                                ],
                                 configurations: [
                                   .debug(settings: [ "OVERRIDEABLE_CONFIG": "Framework2.Debug.Base" ], xcconfig: "../configs/debug.xcconfig"),
                                   .release(settings: [ "OVERRIDEABLE_CONFIG": "Framework2.Release.Base" ], xcconfig: "../configs/release.xcconfig"),
                                   .release(name: "Beta", settings: [ "OVERRIDEABLE_CONFIG": "Framework2.Beta.Base" ], xcconfig: "../configs/beta.xcconfig"),
                                   .debug(name: "Testing", settings: [ "OVERRIDEABLE_CONFIG": "Framework2.Testing.Base" ]),
                                ])

let project = Project(name: "Framework2",
                      targets: [
                        Target(name: "Framework2",
                               platform: .iOS,
                               product: .framework,
                               bundleId: "io.tuist.Framework2",
                               infoPlist: "Config/Framework2-Info.plist",
                               sources: "Sources/**",
                               dependencies: [],
                               settings: targetSettings),
                        Target(name: "Framework2Tests",
                               platform: .iOS,
                               product: .unitTests,
                               bundleId: "io.tuist.Framework2Tests",
                               infoPlist: "Config/Framework2Tests-Info.plist",
                               sources: "Tests/**",
                               dependencies: [
                                .target(name: "Framework2")
                            ]),
                        ])
