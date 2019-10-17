import ProjectDescription

let project = Project(name: "App",
                      targets: [
                        Target(name: "App",
                               platform: .iOS,
                               product: .app,
                               bundleId: "io.tuist.app",
                               infoPlist: "Info.plist",
                               sources: ["Sources/**"],
                               actions: [
                                .pre(path: "/bin/echo", arguments: ["tuist"], name: "Tuist"),
                                .post(path: "/bin/echo", arguments: ["rocks"], name: "Rocks"),
                              ]),
                      ])
