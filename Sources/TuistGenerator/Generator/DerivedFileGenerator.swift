import Basic
import Foundation
import TuistCore
import XcodeProj

protocol DerivedFileGenerating {
    /// Generates the derived files that are associated to the given project.
    ///
    /// - Parameters:
    ///   - project: Project whose derived files will be generated.
    ///   - sourceRootPath: Path to the directory in which the Xcode project will be generated.
    /// - Throws: An error if the generation of the derived files errors.
    /// - Returns: A function to be called after the project generation to delete the derived files that are not necessary anymore.
    func generate(project: Project, sourceRootPath: AbsolutePath) throws -> () throws -> Void
}

final class DerivedFileGenerator: DerivedFileGenerating {
    fileprivate static let derivedFolderName = "Derived"
    fileprivate static let infoPlistsFolderName = "InfoPlists"

    /// File handler instance.
    let fileHandler: FileHandling

    /// Initializes the generator with its attributes.
    ///
    /// - Parameter fileHandler: File handler instance.
    init(fileHandler: FileHandling = FileHandler()) {
        self.fileHandler = fileHandler
    }

    /// Generates the derived files that are associated to the given project.
    ///
    /// - Parameters:
    ///   - project: Project whose derived files will be generated.
    ///   - sourceRootPath: Path to the directory in which the Xcode project will be generated.
    /// - Throws: An error if the generation of the derived files errors.
    /// - Returns: A function to be called after the project generation to delete the derived files that are not necessary anymore.
    func generate(project: Project, sourceRootPath: AbsolutePath) throws -> () throws -> Void {
        /// The files that are not necessary anymore should be deleted after we generate the project.
        /// Otherwise, Xcode will try to reload their references before the project generation.
        var toDelete: Set<AbsolutePath> = []

        toDelete.formUnion(try generateInfoPlists(project: project, sourceRootPath: sourceRootPath))

        return {
            try toDelete.forEach { try self.fileHandler.delete($0) }
        }
    }

    /// Genreates the Info.plist files.
    ///
    /// - Parameters:
    ///   - project: Project that contains the targets whose Info.plist files will be generated.
    ///   - sourceRootPath: Path to the directory in which the project is getting generated.
    /// - Returns: A set with paths to the Info.plist files that are no longer necessary and therefore need to be removed.
    /// - Throws: An error if the encoding of the Info.plist content fails.
    func generateInfoPlists(project: Project, sourceRootPath: AbsolutePath) throws -> Set<AbsolutePath> {
        let infoPlistsPath = DerivedFileGenerator.infoPlistsPath(sourceRootPath: sourceRootPath)
        let targetsWithGeneratableInfoPlists = project.targets.filter {
            guard let infoPlist = $0.infoPlist else { return false }
            guard case InfoPlist.dictionary = infoPlist else { return false }
            return true
        }
        let infoPlistPath: (Target) -> AbsolutePath = { infoPlistsPath.appending(component: "\($0.name).plist") }

        // Getting the Info.plist files that need to be deleted
        let glob = "\(DerivedFileGenerator.derivedFolderName)/\(DerivedFileGenerator.infoPlistsFolderName)/*.plist"
        let existing = fileHandler.glob(sourceRootPath, glob: glob)
        let new: [AbsolutePath] = targetsWithGeneratableInfoPlists.map(infoPlistPath)
        let toDelete = Set(existing).subtracting(new)

        if !fileHandler.exists(infoPlistsPath) {
            try fileHandler.createFolder(infoPlistsPath)
        }

        // Generate the Info.plist
        try targetsWithGeneratableInfoPlists.forEach { target in
            guard let infoPlist = target.infoPlist else { return }
            guard case let InfoPlist.dictionary(dictionary) = infoPlist else { return }

            let path = infoPlistPath(target)
            if fileHandler.exists(path) { try fileHandler.delete(path) }

            let outputDictionary = dictionary.mapValues { $0.value }
            let data = try PropertyListSerialization.data(fromPropertyList: outputDictionary,
                                                          format: .xml,
                                                          options: 0)

            try data.write(to: path.url)
        }

        return toDelete
    }

    /// Returns the path to the directory that contains all the derived files.
    ///
    /// - Parameter sourceRootPath: Directory where the project will be generated.
    /// - Returns: Path to the directory that contains all the derived files.
    static func path(sourceRootPath: AbsolutePath) -> AbsolutePath {
        return sourceRootPath
            .appending(component: DerivedFileGenerator.derivedFolderName)
    }

    /// Returns the path to the directory where all generated Info.plist files will be.
    ///
    /// - Parameter sourceRootPath: Directory where the Xcode project gets genreated.
    /// - Returns: The path to the directory where all the Info.plist files will be generated.
    static func infoPlistsPath(sourceRootPath: AbsolutePath) -> AbsolutePath {
        return path(sourceRootPath: sourceRootPath)
            .appending(component: DerivedFileGenerator.infoPlistsFolderName)
    }
}
