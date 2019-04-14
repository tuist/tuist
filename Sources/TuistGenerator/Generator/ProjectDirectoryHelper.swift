import Basic
import Foundation
import TuistCore

/// Protocol that defines the interface of a class that can be used to set up the directories where projects are generated.
protocol ProjectDirectoryHelping: AnyObject {
    /// Sets up the directory where the project will be generated. For commands like build or test where
    /// the Xcode project is necessary to build the project, the project is generated in the ~/.tuist/DerivedProjects directory.
    /// Optionally, it can be deleted afterwards.
    ///
    /// - Parameters:
    ///   - project: Project that will be generated and whose directory need to be set up.
    ///   - directory: Directory where the
    /// - Returns: The path to the directory where the project should be created.
    /// - Throws: An error if the project directory cannot be set up.
    func setupProjectDirectory(project: Project, directory: GenerationDirectory) throws -> AbsolutePath

    /// Sets up the directory where the element with the given name and path will be generated.
    ///
    /// - Parameters:
    ///   - name: Name of the element whose directory will be set up (workspace or project name).
    ///   - path: Path where the project or workspace is defined. The directory that contains the manifest.
    ///   - directory: Directory where the project will be generated.
    /// - Returns: The path to the directory where the element (workspace or project) should be created.
    /// - Throws: An error if the directory cannot be set up.
    func setupDirectory(name: String, path: AbsolutePath, directory: GenerationDirectory) throws -> AbsolutePath
}

/// Default implementation of the ProjectDirectoryHelping protocol.
class ProjectDirectoryHelper: ProjectDirectoryHelping {
    /// Environment controller instance. It's necessary to obtain the directory where the derived projects are generated into.
    let environmentController: EnvironmentControlling

    /// File handler instance for file operations.
    let fileHandler: FileHandling

    // MARK: - Init

    /// Deafult constructor.
    ///
    /// - Parameter environmentController: Environment controller instance. It's necessary to obtain the directory where the derived projects are generated into.
    /// - Parameter fileHandler: File handler instance for file operations.
    init(environmentController: EnvironmentControlling = EnvironmentController(),
         fileHandler: FileHandling = FileHandler()) {
        self.environmentController = environmentController
        self.fileHandler = fileHandler
    }

    /// Sets up the directory where the project will be generated. For commands like build or test where
    /// the Xcode project is necessary to build the project, the project is generated in the ~/.tuist/DerivedProjects directory.
    /// Optionally, it can be deleted afterwards.
    ///
    /// - Parameters:
    ///   - project: Project that will be generated and whose directory need to be set up.
    ///   - directory: Directory where the project will be generated.
    /// - Returns: The path to the directory where the project should be created.
    /// - Throws: An error if the directory cannot be set up.
    func setupProjectDirectory(project: Project, directory: GenerationDirectory) throws -> AbsolutePath {
        return try setupDirectory(name: project.name,
                                  path: project.path,
                                  directory: directory)
    }

    /// Sets up the directory where the element with the given name and path will be generated.
    ///
    /// - Parameters:
    ///   - name: Name of the element whose directory will be set up (workspace or project name).
    ///   - path: Path where the project or workspace is defined. The directory that contains the manifest.
    ///   - directory: Directory where the project will be generated.
    /// - Returns: The path to the directory where the element (workspace or project) should be created.
    /// - Throws: An error if the directory cannot be set up.
    func setupDirectory(name: String, path: AbsolutePath, directory: GenerationDirectory) throws -> AbsolutePath {
        switch directory {
        case .derivedProjects:
            let md5 = path.pathString.md5
            let path = environmentController.derivedProjectsDirectory.appending(component: "\(name)-\(md5)")
            if !fileHandler.exists(path) {
                try fileHandler.createFolder(path)
            }
            return path
        case .manifest:
            return path
        }
    }
}
