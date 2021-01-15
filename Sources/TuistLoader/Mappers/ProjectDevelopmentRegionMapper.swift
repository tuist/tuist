import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import TuistGraph

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
        if let developmentRegion = developmentRegionOverride() {
            project.developmentRegion = developmentRegion
        }

        return (project, [])
    }

    // MARK: - Private

    /// - Returns: The development region that should be used for the project.
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
