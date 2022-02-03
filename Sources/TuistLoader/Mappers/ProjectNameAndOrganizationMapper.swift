import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// It's a mapper that changes the project name and organization based on the configuration
/// in the Config.swift
public class ProjectNameAndOrganizationMapper: ProjectMapping {
    private let config: TuistGraph.Config

    public init(config: TuistGraph.Config) {
        self.config = config
    }

    // MARK: - ProjectMapping

    public func map(project: TuistGraph.Project) throws -> (TuistGraph.Project, [SideEffectDescriptor]) {
        var project = project

        // Xcode project file name
        if var xcodeFileName = config.generationOptions.xcodeProjectName {
            let projectNameTemplate = TemplateString.Token.projectName.rawValue
            xcodeFileName = xcodeFileName.replacingOccurrences(
                of: projectNameTemplate,
                with: project.name
            )
            project.xcodeProjPath = project.xcodeProjPath.parentDirectory.appending(component: "\(xcodeFileName).xcodeproj")
        }

        // Xcode project organization name
        if let organizationName = config.generationOptions.organizationName {
            project.organizationName = organizationName
        }

        return (project, [])
    }
}
