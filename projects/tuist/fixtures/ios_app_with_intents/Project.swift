import ProjectDescription

let project = Project(name: "App",
                      targets: [
                        Target(name: "App",
                               platform: .iOS,
                               product: .app,
                               bundleId: "io.tuist.app",
                               infoPlist: "Info.plist",
                               sources: [
                                "Sources/**",
                                SourceFileGlob("Intents/Public.intentdefinition", codeGen: .public),
                                SourceFileGlob("Intents/Private.intentdefinition", codeGen: .private),
                                SourceFileGlob("Intents/Project.intentdefinition", codeGen: .project),
                                SourceFileGlob("Intents/Disabled.intentdefinition", codeGen: .disabled)
                               ])
                      ])
