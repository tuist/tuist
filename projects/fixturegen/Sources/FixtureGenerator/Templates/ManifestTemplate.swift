import Foundation

class ManifestTemplate {
    private let workspaceTemplate = """
    import ProjectDescription

    let workspace = Workspace(
        name: "{WorkspaceName}",
        projects: [
    {Projects}
        ])
    """

    private let workspaceProjectTemplate = """
          "{Project}"
    """

    private let projectTemplate = """
    import ProjectDescription

    let project = Project(
        name: "{ProjectName}",
        targets: [
    {Targets}
        ])

    """

    private let targetTemplate = """
            Target(
                name: "{TargetName}",
                platform: .iOS,
                product: .framework,
                bundleId: "io.tuist.{TargetName}",
                infoPlist: .default,
                sources: [
                    "{TargetName}/Sources/**"
                ],
                resources: [

                ],
                dependencies: [
            ])
    """

    func generate(workspaceName: String, projects: [String]) -> String {
        workspaceTemplate
            .replacingOccurrences(of: "{WorkspaceName}", with: workspaceName)
            .replacingOccurrences(of: "{Projects}", with: generate(projects: projects))
    }

    func generate(projectName: String, targets: [String]) -> String {
        projectTemplate
            .replacingOccurrences(of: "{ProjectName}", with: projectName)
            .replacingOccurrences(of: "{Targets}", with: generate(targets: targets))
    }

    private func generate(projects: [String]) -> String {
        projects.map {
            workspaceProjectTemplate.replacingOccurrences(of: "{Project}", with: $0)
        }.joined(separator: ",\n")
    }

    private func generate(targets: [String]) -> String {
        targets.map {
            targetTemplate.replacingOccurrences(of: "{TargetName}", with: $0)
        }.joined(separator: ",\n")
    }
}
