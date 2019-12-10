import ProjectDescription

let customAppScheme = Scheme(name: "Workspace-App",
                                      shared: true,
                                      buildAction: BuildAction(targets: [.project(path: "App", target: "App")], preActions: []),
                                      testAction: TestAction(targets: [TestableTarget(target: .project(path: "App", target: "AppTests"),
                                                                                              .project(path: "Frameworks/Framework1", target: "Framework1Tests"),
                                                                                              .project(path: "Frameworks/Framework2", target: "Framework2Tests"))]),
                                      runAction: RunAction(executable: .project(path: "App", target: "App")),
                                      archiveAction: ArchiveAction(configurationName: "Debug", customArchiveName: "Something2"))

let customFrameworkScheme = Scheme(name: "Workspace-Framework",
                                            shared: true,
                                            buildAction: BuildAction(targets: [.project(path: "Frameworks/Framework1", target: "Framework1")], preActions: []),
                                            testAction: TestAction(targets: [TestableTarget(target: .project(path: "Frameworks/Framework1", target: "Framework1Tests"))]),
                                            archiveAction: ArchiveAction(configurationName: "Debug", customArchiveName: "Something2"))

let workspace = Workspace(name: "Workspace",
                          projects: [
                              "App",
                              "Frameworks/**",
                            ],
                            schemes: [
                              customAppScheme,
                              customFrameworkScheme
                            ])
