import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

/// Mapper that changes the development region based on configuration
/// in the Config.swift
public class DevelopmentRegionMapper: ProjectMapping {
    private let config: TuistCore.Config

    public init(config: TuistCore.Config) {
        self.config = config
    }

    // MARK: - ProjectMapping

    public func map(project: TuistCore.Project) throws -> (TuistCore.Project, [SideEffectDescriptor]) {
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
