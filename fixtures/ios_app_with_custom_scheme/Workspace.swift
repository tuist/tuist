import ProjectDescription

let customAppScheme = WorkspaceScheme(name: "Workspace-App",
                                      shared: true,
                                      buildAction: .buildAction(targets: [.project(path: "App", target: "App")], preActions: []),
                                      testAction: .testAction(targets: [.testableTarget(target: .project(path: "App", target: "AppTests"))]),
                                      runAction: .runAction(executable: .project(path: "App", target: "App")),
                                      archiveAction: .archiveAction(configurationName: "Debug", customArchiveName: "Something2"))

let customFrameworkScheme = WorkspaceScheme(name: "Workspace-Framework",
                                            shared: true,
                                            buildAction: .buildAction(targets: [.project(path: "Frameworks/Framework1", target: "Framework1")], preActions: []),
                                            testAction: .testAction(targets: [.testableTarget(target: .project(path: "Frameworks/Framework1", target: "Framework1Tests"))]),
                                            archiveAction: .archiveAction(configurationName: "Debug", customArchiveName: "Something2"))

let workspace = Workspace(name: "Workspace",
                          projects: [
                              "App",
                              "Frameworks/**",
                            ],
                            schemes: [
                              customAppScheme,
                              customFrameworkScheme
                            ])
