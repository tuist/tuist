import Basic
import Foundation
import TuistCore
import xcodeproj

/// Headers
class Headers: GraphInitiatable, Equatable {
    // MARK: - Attributes

    let `public`: [AbsolutePath]
    let `private`: [AbsolutePath]
    let project: [AbsolutePath]

    // MARK: - Init

    init(public: [AbsolutePath],
         private: [AbsolutePath],
         project: [AbsolutePath]) {
        self.public = `public`
        self.private = `private`
        self.project = project
    }

    /// Default constructor of entities that are part of the manifest.
    ///
    /// - Parameters:
    ///   - dictionary: Dictionary with the object representation.
    ///   - projectPath: Absolute path to the folder that contains the manifest. This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
    ///   - fileHandler: File handler for any file operations like checking whether a file exists or not.
    /// - Throws: A decoding error if an expected property is missing or has an invalid value.
    required init(dictionary: JSON, projectPath: AbsolutePath, fileHandler _: FileHandling) throws {
        if let `public`: String = try? dictionary.get("public") {
            self.public = projectPath.glob(`public`)
        } else {
            `public` = []
        }

        if let `private`: String = try? dictionary.get("private") {
            self.private = projectPath.glob(`private`)
        } else {
            `private` = []
        }

        if let project: String = try? dictionary.get("project") {
            self.project = projectPath.glob(project)
        } else {
            project = []
        }
    }

    // MARK: - Equatable

    static func == (lhs: Headers, rhs: Headers) -> Bool {
        return lhs.public == rhs.public &&
            lhs.private == rhs.private &&
            lhs.project == rhs.project
    }
}
