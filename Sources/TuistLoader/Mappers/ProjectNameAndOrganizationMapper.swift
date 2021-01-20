import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport
import TuistGraph

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
        if let xcodeFileName = xcodeFileNameOverride(for: project) {
            project.xcodeProjPath = project.xcodeProjPath.parentDirectory.appending(component: "\(xcodeFileName).xcodeproj")
        }

        // Xcode project organization name
        if let organizationName = organizationNameOverride() {
            project.organizationName = organizationName
        }

        return (project, [])
    }

    // MARK: - Private

    /// It returns the name that should be used for the given project.
    /// - Parameter project: Project representation.
    /// - Returns: The name to be used.
    private func xcodeFileNameOverride(for project: TuistGraph.Project) -> String? {
        var xcodeFileName = config.generationOptions.compactMap { item -> String? in
            switch item {
            case let .xcodeProjectName(projectName):
                return projectName.description
            default:
                return nil
            }
        }.first

        let projectNameTemplate = TemplateString.Token.projectName.rawValue
        xcodeFileName = xcodeFileName?.replacingOccurrences(of: projectNameTemplate,
                                                            with: project.name)

        return xcodeFileName
    }

    /// - Returns: The organization name that should be used for the project.
    private func organizationNameOverride() -> String? {
        config.generationOptions.compactMap { item -> String? in
            switch item {
            case let .organizationName(name):
                return name
            default:
                return nil
            }
        }.first
    }
}
