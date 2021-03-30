import ProjectDescription

let workspace = Workspace(name: "Workspace",
                          projects: [
                              "App", 
                              "Frameworks/**", 
                            ],
                            additionalFiles: [
                                "Documentation/**",
                                .folderReference(path: "Website")
                            ])
