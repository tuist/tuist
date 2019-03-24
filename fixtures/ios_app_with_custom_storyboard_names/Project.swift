import ProjectDescription

let project = Project(name: "App",
                      targets: [
                        Target(name: "App",
                               platform: .iOS,
                               product: .app,
                               bundleId: "io.tuist.custom-storyboard-names",
                               infoPlist: "Info.plist",
                               mainStoryboard: "Custom Main",
                               launchScreenStoryboard: "Custom Launch Screen",
                               sources: ["Sources/**"],
                               resources: ["Resources/**", "Sources/**/*.storyboard"],
                               dependencies: [
                                /* Target dependencies can be defined here */
                                /* .framework(path: "framework") */
                            ])
    ])
