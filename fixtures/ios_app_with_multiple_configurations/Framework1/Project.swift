import ProjectDescription

let projectSettings = Settings(base: [ 
                                   "CONFIG_SOURCE": "Framework1.Project.Base",
                                   "FRAMEWORK1_BASE": "YES",
                                ],
                                 configurations: [
                                   .debug(settings: [ "OVERRIDEABLE_CONFIG": "Framework1.Debug.Base" ], xcconfig: "../configs/debug.xcconfig"),
                                   .release(settings: [ "OVERRIDEABLE_CONFIG": "Framework1.Release.Base" ], xcconfig: "../configs/release.xcconfig"),
                                   .release(name: "Beta", settings: [ "OVERRIDEABLE_CONFIG": "Framework1.Beta.Base" ], xcconfig: "../configs/beta.xcconfig"),
                                   .debug(name: "Testing", settings: [ "OVERRIDEABLE_CONFIG": "Framework1.Testing.Base" ]),
                                ])

let project = Project(name: "Framework1",
                      settings: projectSettings,
                      targets: [
                        Target(name: "Framework1",
                               platform: .iOS,
                               product: .framework,
                               bundleId: "io.tuist.Framework1",
                               infoPlist: "Config/Framework1-Info.plist",
                               sources: "Sources/**",
                               dependencies: [
                                .project(target: "Framework2", path: "../Framework2")
                               ]),
                        Target(name: "Framework1Tests",
                               platform: .iOS,
                               product: .unitTests,
                               bundleId: "io.tuist.Framework1Tests",
                               infoPlist: "Config/Framework1Tests-Info.plist",
                               sources: "Tests/**",
                               dependencies: [
                                .target(name: "Framework1")
                               ]),
                      ])

