import ProjectDescription

let modules: [Path] = [
    "Modules/ModuleA",
]

let workspace = Workspace(
    name: "Workspace",
    projects: modules,
    schemes: []
)
