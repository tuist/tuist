import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

public class GeneratorModelLoader: GeneratorModelLoading {
    private let manifestLoader: ManifestLoading
    private let manifestLinter: ManifestLinting

    public init(manifestLoader: ManifestLoading,
                manifestLinter: ManifestLinting) {
        self.manifestLoader = manifestLoader
        self.manifestLinter = manifestLinter
    }

    /// Load a Project model at the specified path
    ///
    /// - Parameters:
    ///   - path: The absolute path for the project model to load.
    /// - Returns: The Project loaded from the specified path
    /// - Throws: Error encountered during the loading process (e.g. Missing project)
    public func loadProject(at path: AbsolutePath) throws -> TuistCore.Project {
        let manifest = try manifestLoader.loadProject(at: path)
        let tuistConfig = try loadTuistConfig(at: path)
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        try manifestLinter.lint(project: manifest).printAndThrowIfNeeded()
        let project = try TuistCore.Project.from(manifest: manifest, generatorPaths: generatorPaths)
        return try enriched(model: project, with: tuistConfig)
    }

    public func loadWorkspace(at path: AbsolutePath) throws -> TuistCore.Workspace {
        let manifest = try manifestLoader.loadWorkspace(at: path)
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        let workspace = try TuistCore.Workspace.from(manifest: manifest,
                                                     path: path,
                                                     generatorPaths: generatorPaths,
                                                     manifestLoader: manifestLoader)
        return workspace
    }

    public func loadTuistConfig(at path: AbsolutePath) throws -> TuistCore.TuistConfig {
        guard let tuistConfigPath = FileHandler.shared.locateDirectoryTraversingParents(from: path, path: Manifest.tuistConfig.fileName) else {
            return TuistCore.TuistConfig.default
        }

        let manifest = try manifestLoader.loadTuistConfig(at: tuistConfigPath.parentDirectory)
        return try TuistCore.TuistConfig.from(manifest: manifest)
    }

    private func enriched(model: TuistCore.Project,
                          with config: TuistCore.TuistConfig) throws -> TuistCore.Project {
        var enrichedModel = model

        // Xcode project file name
        let xcodeFileName = xcodeFileNameOverride(from: config, for: model)
        enrichedModel = enrichedModel.replacing(fileName: xcodeFileName)

        return enrichedModel
    }

    private func xcodeFileNameOverride(from config: TuistCore.TuistConfig,
                                       for model: TuistCore.Project) -> String? {
        var xcodeFileName = config.generationOptions.compactMap { item -> String? in
            switch item {
            case let .xcodeProjectName(projectName):
                return projectName.description
            }
        }.first

        let projectNameTemplate = TemplateString.Token.projectName.rawValue
        xcodeFileName = xcodeFileName?.replacingOccurrences(of: projectNameTemplate,
                                                            with: model.name)

        return xcodeFileName
    }
}
