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

    /// Initializes the generator with its attributes.
    ///
    /// - Parameters:
    ///   - projectGenerator: ProjectGenerator
    ///   - fileHandler: Instance to interact with the file system.
    init(projectGenerator: ProjectGenerating = ProjectGenerator(),
         fileHandler: FileHandling = FileHandler()) {
        self.projectGenerator = projectGenerator
        self.fileHandler = fileHandler
    }

    func generate(project: Project, sourceRootPath: AbsolutePath) throws -> AbsolutePath {
        try forceCreateManifestProjectsDirectory(sourceRootPath: sourceRootPath)

        let manifestProject = self.manifestProject(for: project, sourceRootPath: sourceRootPath)
        let graph = Graph(name: manifestProject.name, entryPath: manifestProject.path)
        let generatedProject = try projectGenerator.generate(project: manifestProject,
                                                             graph: graph,
                                                             sourceRootPath: manifestProject.path)
        return generatedProject.path
    }

    func manifestProject(for project: Project, sourceRootPath: AbsolutePath) -> Project {
        let projectName = "\(project.name)-Manifests"
        let manifestProjectsDirectory = self.manifestProjectsDirectory(sourceRootPath: sourceRootPath)

        let target = Target(name: "X",
                            platform: .macOS,
                            product: .staticFramework,
                            productName: "X.framework",
                            bundleId: "io.tuist.X",
                            filesGroup: .group(name: "X"))

        return Project(path: manifestProjectsDirectory,
                       name: projectName,
                       settings: Settings(base: [:],
                                          configurations: [.debug: Configuration(settings: [:], xcconfig: nil),
                                                           .release: Configuration(settings: [:], xcconfig: nil)],
                                          defaultSettings: .recommended),
                       filesGroup: .group(name: "X"),
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

//    func manifestTargetBuildSettings() throws -> [String: String] {
//        let frameworkParentDirectory = try resourceLocator.projectDescription().parentDirectory
//        var buildSettings = [String: String]()
//        buildSettings["FRAMEWORK_SEARCH_PATHS"] = frameworkParentDirectory.pathString
//        buildSettings["LIBRARY_SEARCH_PATHS"] = frameworkParentDirectory.pathString
//        buildSettings["SWIFT_INCLUDE_PATHS"] = frameworkParentDirectory.pathString
//        buildSettings["SWIFT_VERSION"] = Constants.swiftVersion
//        return buildSettings
//    }

    func manifestProjectsDirectory(sourceRootPath: AbsolutePath) -> AbsolutePath {
        return sourceRootPath
            .appending(component: Constants.derivedFolderName)
            .appending(component: "ManifestProjects")
    }
}

// class ManifestTargetGenerator: ManifestTargetGenerating {
//    private let manifestLoader: GraphManifestLoading
//    private let resourceLocator: ResourceLocating
//
//    init(manifestLoader: GraphManifestLoading,
//         resourceLocator: ResourceLocating) {
//        self.manifestLoader = manifestLoader
//        self.resourceLocator = resourceLocator
//    }
//
//    func generateManifestTarget(for project: String,
//                                at path: AbsolutePath) throws -> Target {
//        let settings = Settings(base: try manifestTargetBuildSettings(),
//                                configurations: Settings.default.configurations,
//                                defaultSettings: .recommended)
//        let manifests = manifestLoader.manifests(at: path)
//
//        return Target(name: "\(project)_Manifest",
//            platform: .macOS,
//            product: .staticFramework,
//            productName: "\(project)_Manifest",
//            bundleId: "io.tuist.manifests.${PRODUCT_NAME:rfc1034identifier}",
//            settings: settings,
//            sources: manifests.map { (path: path.appending(component: $0.fileName), compilerFlags: nil) },
//            filesGroup: .group(name: "Manifest"))
//    }
//
// }
