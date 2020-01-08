import Basic
import Foundation
import TuistCore
import TuistSupport
import XcodeProj

protocol DerivedFileGenerating {
    /// Generates the derived files that are associated to the given project.
    ///
    /// - Parameters:
    ///   - graph: The dependencies graph.
    ///   - project: Project whose derived files will be generated.
    ///   - sourceRootPath: Path to the directory in which the Xcode project will be generated.
    /// - Throws: An error if the generation of the derived files errors.
    /// - Returns: A project that might have got mutated after the generation of derived files, and a
    ///     function to be called after the project generation to delete the derived files that are not necessary anymore.
    func generate(graph: Graphing, project: Project, sourceRootPath: AbsolutePath) throws -> (Project, () throws -> Void)
}

final class DerivedFileGenerator: DerivedFileGenerating {
    fileprivate static let derivedFolderName = "Derived"
    fileprivate static let infoPlistsFolderName = "InfoPlists"

    /// Info.plist content provider.
    let infoPlistContentProvider: InfoPlistContentProviding

    /// Initializes the generator with its attributes.
    ///
    /// - Parameters:
    ///   - infoPlistContentProvider: Info.plist content provider.
    init(infoPlistContentProvider: InfoPlistContentProviding = InfoPlistContentProvider()) {
        self.infoPlistContentProvider = infoPlistContentProvider
    }

    func generate(graph: Graphing, project: Project, sourceRootPath: AbsolutePath) throws -> (Project, () throws -> Void) {
        /// The files that are not necessary anymore should be deleted after we generate the project.
        /// Otherwise, Xcode will try to reload their references before the project generation.
        var toDelete: Set<AbsolutePath> = []
        let (project, infoPlistsToDelete) = try generateInfoPlists(graph: graph, project: project, sourceRootPath: sourceRootPath)

        toDelete.formUnion(infoPlistsToDelete)

        return (project, {
            try toDelete.forEach { try FileHandler.shared.delete($0) }
        })
    }

    /// Genreates the Info.plist files.
    ///
    /// - Parameters:
    ///   - graph: The dependencies graph.
    ///   - project: Project that contains the targets whose Info.plist files will be generated.
    ///   - sourceRootPath: Path to the directory in which the project is getting generated.
    /// - Returns: A set with paths to the Info.plist files that are no longer necessary and therefore need to be removed.
    /// - Throws: An error if the encoding of the Info.plist content fails.
    func generateInfoPlists(graph: Graphing, project: Project, sourceRootPath: AbsolutePath) throws -> (Project, Set<AbsolutePath>) {
        let infoPlistsPath = DerivedFileGenerator.infoPlistsPath(sourceRootPath: sourceRootPath)
        let targetsWithGeneratableInfoPlists = project.targets.filter {
            if let infoPlist = $0.infoPlist, case InfoPlist.file = infoPlist {
                return false
            }
            return true
        }

        // Getting the Info.plist files that need to be deleted
        let glob = "\(DerivedFileGenerator.derivedFolderName)/\(DerivedFileGenerator.infoPlistsFolderName)/*.plist"
        let existing = FileHandler.shared.glob(sourceRootPath, glob: glob)
        let new: [AbsolutePath] = targetsWithGeneratableInfoPlists.map {
            DerivedFileGenerator.infoPlistPath(target: $0, sourceRootPath: sourceRootPath)
        }
        let toDelete = Set(existing).subtracting(new)

        if !FileHandler.shared.exists(infoPlistsPath), !targetsWithGeneratableInfoPlists.isEmpty {
            try FileHandler.shared.createFolder(infoPlistsPath)
        }

        // Generate the Info.plist
        let newTargets = try project.targets.map { (target) -> Target in
            guard targetsWithGeneratableInfoPlists.contains(target) else { return target }

            guard let infoPlist = target.infoPlist else { return target }

            let dictionary: [String: Any]

            if case let InfoPlist.dictionary(content) = infoPlist {
                dictionary = content.mapValues { $0.value }
            } else if case let InfoPlist.extendingDefault(extended) = infoPlist,
                let content = self.infoPlistContentProvider.content(graph: graph,
                                                                    project: project,
                                                                    target: target,
                                                                    extendedWith: extended) {
                dictionary = content
            } else {
                return target
            }

            let path = DerivedFileGenerator.infoPlistPath(target: target, sourceRootPath: sourceRootPath)
            if FileHandler.shared.exists(path) { try FileHandler.shared.delete(path) }

            let data = try PropertyListSerialization.data(fromPropertyList: dictionary,
                                                          format: .xml,
                                                          options: 0)

            try data.write(to: path.url)

            // Override the Info.plist value to point to te generated one
            return target.with(infoPlist: InfoPlist.file(path: path))
        }

        return (project.with(targets: newTargets), toDelete)
    }

    /// Returns the path to the directory that contains all the derived files.
    ///
    /// - Parameter sourceRootPath: Directory where the project will be generated.
    /// - Returns: Path to the directory that contains all the derived files.
    static func path(sourceRootPath: AbsolutePath) -> AbsolutePath {
        sourceRootPath
            .appending(component: DerivedFileGenerator.derivedFolderName)
    }

    /// Returns the path to the directory where all generated Info.plist files will be.
    ///
    /// - Parameter sourceRootPath: Directory where the Xcode project gets genreated.
    /// - Returns: The path to the directory where all the Info.plist files will be generated.
    static func infoPlistsPath(sourceRootPath: AbsolutePath) -> AbsolutePath {
        path(sourceRootPath: sourceRootPath)
            .appending(component: DerivedFileGenerator.infoPlistsFolderName)
    }

    /// Returns the path where the derived Info.plist is generated.
    ///
    /// - Parameters:
    ///   - target: The target the InfoPlist belongs to.
    ///   - sourceRootPath: The directory where the Xcode project will be generated.
    /// - Returns: The path where the derived Info.plist is generated.
    static func infoPlistPath(target: Target, sourceRootPath: AbsolutePath) -> AbsolutePath {
        infoPlistsPath(sourceRootPath: sourceRootPath)
            .appending(component: "\(target.name).plist")
    }
}
