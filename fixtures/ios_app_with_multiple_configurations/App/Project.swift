import ProjectDescription


let projectSettings = Settings(base: [
                            "CONFIG_SOURCE": "MainApp.Project.Base",
                            "MAINAPP_BASE": "YES",
                        ],
                        configurations: [
                            .debug(settings: [ "OVERRIDEABLE_CONFIG": "Debug.Base" ], xcconfig: "../configs/debug.xcconfig"),
                            .release(settings: [ "OVERRIDEABLE_CONFIG": "Release.Base" ], xcconfig: "../configs/release.xcconfig"),
                            .release(name: "Beta", settings: [ "OVERRIDEABLE_CONFIG": "Beta.Base" ], xcconfig: "../configs/beta.xcconfig"),
                        ])

let targetSettings = Settings(base: [
                                    "CONFIG_SOURCE": "MainApp.AppTarget.Base",
                                    "APPTARGET_BASE": "YES",
                                ],
                              configurations: [
                                .debug(settings: [ "OVERRIDEABLE_CONFIG": "AppTarget.Debug.Base" ]),
                                .release(settings: [ "OVERRIDEABLE_CONFIG": "AppTarget.Release.Base" ]),
                                .release(name: "Beta", settings: [ "OVERRIDEABLE_CONFIG": "AppTarget.Beta.Base" ]),
                                .debug(name: "Testing", settings: [ "OVERRIDEABLE_CONFIG": "AppTarget.Testing.Base" ]),
                            ])

let project = Project(name: "MainApp",
                      settings: projectSettings,
                      targets: [
                        Target(name: "App",
                               platform: .iOS,
                               product: .app,
                               bundleId: "io.tuist.App",
                               infoPlist: "Config/App-Info.plist",
                               sources: "Sources/**",
                               dependencies: [
                                    .project(target: "Framework1", path: "../Framework1"),
                                    .project(target: "Framework2", path: "../Framework2")
                                ],
                               settings: targetSettings),
                        Target(name: "AppTests",
                               platform: .iOS,
                               product: .unitTests,
                               bundleId: "io.tuist.AppTests",
                               infoPlist: "Config/AppTests-Info.plist",
                               sources: "Tests/**",
                               dependencies: [
                                .target(name: "App")
                            ])
                        ])
