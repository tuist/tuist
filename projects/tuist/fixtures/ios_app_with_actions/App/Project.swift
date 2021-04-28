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
                                .pre(tool: "/bin/echo", arguments: ["\"tuist\""], name: "Tuist", inputPaths: ["Sources/**/*.swift"]),
                                .post(tool: "/bin/echo", arguments: ["rocks"], name: "Rocks"),
                                .pre(path: "script.sh", name: "Run script"),
                                .pre(script: "echo 'Hello World'", name: "Embedded script"),
                              ]),
                      ])
