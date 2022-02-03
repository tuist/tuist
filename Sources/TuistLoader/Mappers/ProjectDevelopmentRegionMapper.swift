import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// Mapper that changes the development region based on configuration
/// in the Config.swift
public final class ProjectDevelopmentRegionMapper: ProjectMapping {
    private let config: TuistGraph.Config

    public init(config: TuistGraph.Config) {
        self.config = config
    }

    // MARK: - ProjectMapping

    public func map(project: TuistGraph.Project) throws -> (TuistGraph.Project, [SideEffectDescriptor]) {
        var project = project

        // Xcode project development region
        if let developmentRegion = config.generationOptions.developmentRegion {
            project.developmentRegion = developmentRegion
        }

        return (project, [])
    }
}
