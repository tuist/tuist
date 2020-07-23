import ProjectDescription

let project = Project(name: "App",
                      targets: [
                        Target(name: "App",
                               platform: .iOS,
                               product: .app,
                               bundleId: "io.tuist.app",
                               infoPlist: "Info.plist",
                               sources: ["Sources/**"],
                               dependencies: [
                                    .cocoapods(path: ".")
                                ]),
                      ])
