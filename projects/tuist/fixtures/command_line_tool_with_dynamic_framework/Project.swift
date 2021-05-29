import ProjectDescription

let project = Project(name: "CommandLineTool",
                      targets: [
                        Target(name: "CommandLineTool",
                               platform: .macOS,
                               product: .commandLineTool,
                               bundleId: "com.example.commandlinetool",
                               infoPlist: .default,
                               dependencies: [
                                .target(name: "DynamicFramework"),
                                .target(name: "DynamicLib"),
                               ]),
                        Target(name: "DynamicFramework",
                               platform: .macOS,
                               product: .framework,
                               bundleId: "com.example.dynamicframework",
                               infoPlist: .default),
])
