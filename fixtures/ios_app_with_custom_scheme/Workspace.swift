import ProjectDescription

let releaseScheme = WorkspaceDescription.Scheme(name: "App-Release",
                                                shared: true,
                                                buildAction: WorkspaceDescription.BuildAction(targets: [.project(path: "App", target: "App")], preActions: []),
                                                testAction: WorkspaceDescription.TestAction(targets: [WorkspaceDescription.TestableTarget(target: WorkspaceDescription.TargetReference.project(path: "App", target: "AppTests"))]),
                                                runAction: WorkspaceDescription.RunAction(executable: .project(path: "App", target: "App")))

let workspace = Workspace(name: "Workspace",
                          projects: [
                              "App",
                              "Frameworks/**",
                            ],
                            schemes: [
                              releaseScheme
                            ])
