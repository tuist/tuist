import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

/// It's a mapper that changes the project name and organization based on the configuration
/// in the Config.swift
public class ProjectNameAndOrganizationMapper: ProjectMapping {
    private let config: TuistCore.Config

    public init(config: TuistCore.Config) {
        self.config = config
    }

    // MARK: - ProjectMapping

    public func map(project: TuistCore.Project) throws -> (TuistCore.Project, [SideEffectDescriptor]) {
        var project = project

        // Xcode project file name
        if let xcodeFileName = xcodeFileNameOverride(for: project) {
            project.xcodeProjPath = project.xcodeProjPath.parentDirectory.appending(component: "\(xcodeFileName).xcodeproj")
        }

        // Xcode project organization name
        if let organizationName = organizationNameOverride() {
            project.organizationName = organizationName
        }
        
        // Xcode project development region
        if let developmentRegion = developmentRegionOverride() {
            project.developmentRegion = developmentRegion
        }

        return (project, [])
    }

    // MARK: - Private

    /// It returns the name that should be used for the given project.
    /// - Parameter project: Project representation.
    /// - Returns: The name to be used.
    private func xcodeFileNameOverride(for project: TuistCore.Project) -> String? {
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

    /// It returns the organization name that should be used for the project.
    /// - Returns: The organization name.
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
    
    /// It returns the development region that should be used for the project.
    /// - Returns: The development region.
    private func developmentRegionOverride() -> String? {
        config.generationOptions.compactMap { item -> String? in
            switch item {
            case let .developmentRegion(developmentRegion):
                return developmentRegion
            default:
                return nil
            }
        }.first
    }
}
