import ProjectDescription

let workspace = Workspace(
    name: "Workspace",
    projects: [
        "App",
        "Modules/**"
    ],
    additionalFiles: [
        "Workspace.swift",
        "*.playground",
        "Documentation/**/*.md",
        "../ios_app_with_setup/Setup.swift"
    ]
)
