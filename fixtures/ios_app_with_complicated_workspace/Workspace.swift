import ProjectDescription

let workspace = Workspace(name: "Workspace",
                          projects: ["App", "Modules/*"]
                          additionalFiles: ["Workspace.swift", "*.playground"])
