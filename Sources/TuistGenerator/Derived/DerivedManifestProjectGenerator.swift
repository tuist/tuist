import Basic
import Foundation
import TuistCore

protocol DerivedManifestProjectGenerating {
    func generate(project: Project, sourceRootPath: AbsolutePath) throws -> AbsolutePath
}

final class DerivedManifestProjectGenerator: DerivedManifestProjectGenerating {
    /// Project generator.
    private let projectGenerator: ProjectGenerating

    /// File handler to interact with the file system.
    private let fileHandler: FileHandling

    /// Resource locator.
    private let resourceLocator: ResourceLocating

    /// Initializes the generator with its attributes.
    ///
    /// - Parameters:
    ///   - projectGenerator: ProjectGenerator
    ///   - fileHandler: Instance to interact with the file system.
    init(projectGenerator: ProjectGenerating = ProjectGenerator(),
         fileHandler: FileHandling = FileHandler(),
         resourceLocator: ResourceLocating = ResourceLocator()) {
        self.projectGenerator = projectGenerator
        self.fileHandler = fileHandler
        self.resourceLocator = resourceLocator
    }

    func generate(project: Project, sourceRootPath: AbsolutePath) throws -> AbsolutePath {
        try forceCreateManifestProjectsDirectory(sourceRootPath: sourceRootPath)

        let manifestProject = try self.manifestProject(for: project, sourceRootPath: sourceRootPath)
        let graph = Graph(name: manifestProject.name, entryPath: manifestProject.path)
        let generatedProject = try projectGenerator.generate(project: manifestProject,
                                                             graph: graph,
                                                             sourceRootPath: manifestProject.path)
        return generatedProject.path
    }

    func manifestProject(for project: Project, sourceRootPath: AbsolutePath) throws -> Project {
        let projectName = "\(project.name)-Project"
        let manifestProjectsDirectory = self.manifestProjectsDirectory(sourceRootPath: sourceRootPath)

        let settings = Settings(base: try manifestTargetBuildSettings(),
                                configurations: Settings.default.configurations,
                                defaultSettings: .recommended)

        let target = Target(name: "\(project)-Project",
                            platform: .macOS,
                            product: .staticFramework,
                            productName: "\(project)-Project",
                            bundleId: "io.tuist.manifests.${PRODUCT_NAME:rfc1034identifier}",
                            settings: settings,
                            sources: [(path: sourceRootPath.appending(component: "Project.swift"), compilerFlags: nil)],
                            filesGroup: .group(name: "Manifests"))

        return Project(path: manifestProjectsDirectory,
                       name: projectName,
                       settings: settings,
                       filesGroup: .group(name: project.name),
                       targets: [target],
                       schemes: [],
                       additionalFiles: [])
    }

    func forceCreateManifestProjectsDirectory(sourceRootPath: AbsolutePath) throws {
        let manifestProjectsDirectory = self.manifestProjectsDirectory(sourceRootPath: sourceRootPath)

        if fileHandler.exists(manifestProjectsDirectory) {
            try fileHandler.delete(manifestProjectsDirectory)
        }

        try fileHandler.createFolder(manifestProjectsDirectory)
    }

    func manifestTargetBuildSettings() throws -> [String: String] {
        let frameworkParentDirectory = try resourceLocator.projectDescription().parentDirectory
        var buildSettings = [String: String]()
        buildSettings["FRAMEWORK_SEARCH_PATHS"] = frameworkParentDirectory.pathString
        buildSettings["LIBRARY_SEARCH_PATHS"] = frameworkParentDirectory.pathString
        buildSettings["SWIFT_INCLUDE_PATHS"] = frameworkParentDirectory.pathString
        buildSettings["SWIFT_VERSION"] = Constants.swiftVersion
        return buildSettings
    }

    func manifestProjectsDirectory(sourceRootPath: AbsolutePath) -> AbsolutePath {
        return sourceRootPath
            .appending(component: Constants.derivedFolderName)
            .appending(component: "ManifestProjects")
    }
}
