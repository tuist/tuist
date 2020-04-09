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
    func generate(graph: Graph, project: Project, sourceRootPath: AbsolutePath) throws -> (Project, [SideEffectDescriptor])
}

final class DerivedFileGenerator: DerivedFileGenerating {
    typealias ProjectTransformation = (project: Project, sideEffects: [SideEffectDescriptor])
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

    func generate(graph: Graph, project: Project, sourceRootPath: AbsolutePath) throws -> (Project, [SideEffectDescriptor]) {
        let transformation = try generateInfoPlists(graph: graph, project: project, sourceRootPath: sourceRootPath)

        return (transformation.project, transformation.sideEffects)
    }

    /// Genreates the Info.plist files.
    ///
    /// - Parameters:
    ///   - graph: The dependencies graph.
    ///   - project: Project that contains the targets whose Info.plist files will be generated.
    ///   - sourceRootPath: Path to the directory in which the project is getting generated.
    /// - Returns: A set with paths to the Info.plist files that are no longer necessary and therefore need to be removed.
    /// - Throws: An error if the encoding of the Info.plist content fails.
    func generateInfoPlists(graph: Graph,
                            project: Project,
                            sourceRootPath: AbsolutePath) throws -> ProjectTransformation {
        let targetsWithGeneratableInfoPlists = project.targets.filter {
            if let infoPlist = $0.infoPlist, case InfoPlist.file = infoPlist {
                return false
            }
            return true
        }

        // Getting the Info.plist files that need to be deleted
        let glob = "\(Constants.DerivedFolder.name)/\(DerivedFileGenerator.infoPlistsFolderName)/*.plist"
        let existing = FileHandler.shared.glob(sourceRootPath, glob: glob)
        let new: [AbsolutePath] = targetsWithGeneratableInfoPlists.map {
            DerivedFileGenerator.infoPlistPath(target: $0, sourceRootPath: sourceRootPath)
        }
        let toDelete = Set(existing).subtracting(new)

        let deletions = toDelete.map {
            SideEffectDescriptor.file(FileDescriptor(path: $0, state: .absent))
        }

        // Generate the Info.plist
        let transformation = try project.targets.map { (target) -> (Target, [SideEffectDescriptor]) in
            guard targetsWithGeneratableInfoPlists.contains(target),
                let infoPlist = target.infoPlist else {
                return (target, [])
            }

            guard let dictionary = infoPlistDictionary(infoPlist: infoPlist,
                                                       project: project,
                                                       target: target,
                                                       graph: graph) else {
                return (target, [])
            }

            let path = DerivedFileGenerator.infoPlistPath(target: target, sourceRootPath: sourceRootPath)

            let data = try PropertyListSerialization.data(fromPropertyList: dictionary,
                                                          format: .xml,
                                                          options: 0)

            let sideEffet = SideEffectDescriptor.file(FileDescriptor(path: path, contents: data))

            // Override the Info.plist value to point to te generated one
            return (target.with(infoPlist: InfoPlist.file(path: path)), [sideEffet])
        }

        return (project: project.with(targets: transformation.map { $0.0 }),
                sideEffects: deletions + transformation.flatMap { $0.1 })
    }

    private func infoPlistDictionary(infoPlist: InfoPlist,
                                     project: Project,
                                     target: Target,
                                     graph: Graph) -> [String: Any]? {
        switch infoPlist {
        case let .dictionary(content):
            return content.mapValues { $0.value }
        case let .extendingDefault(extended):
            if let content = infoPlistContentProvider.content(graph: graph,
                                                              project: project,
                                                              target: target,
                                                              extendedWith: extended) {
                return content
            }
            return nil
        default:
            return nil
        }
    }

    /// Returns the path to the directory that contains all the derived files.
    ///
    /// - Parameter sourceRootPath: Directory where the project will be generated.
    /// - Returns: Path to the directory that contains all the derived files.
    static func path(sourceRootPath: AbsolutePath) -> AbsolutePath {
        sourceRootPath.appending(component: Constants.DerivedFolder.name)
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
