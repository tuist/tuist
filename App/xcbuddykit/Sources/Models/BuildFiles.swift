import Basic
import Foundation

// MARK: - BuildFiles

class BuildFiles: GraphJSONInitiatable {
    /// Files.
    let files: Set<AbsolutePath>

    /// Initializes the object with a set of build files.
    ///
    /// - Parameter files: build files.
    init(files: Set<AbsolutePath> = Set()) {
        self.files = files
    }

    /// Initializes the build files from its JSON representation.
    ///
    /// - Parameters:
    ///   - json: build files JSON representation.
    ///   - projectPath: path to the folder that contains the project's manifest.
    ///   - context: graph loader  context.
    /// - Throws: an error if build files cannot be parsed.
    required init(json: JSON, projectPath: AbsolutePath, context: GraphLoaderContexting) throws {
        if case let JSON.array(buildFilesArray) = json {
            var included: [AbsolutePath] = []
            var excluded: [AbsolutePath] = []
            try buildFilesArray.forEach { buildFiles in
                let type: String = try buildFiles.get("type")
                let paths: [String] = try buildFiles.get("paths")
                if type == "include" {
                    included.append(contentsOf: paths.flatMap({ context.fileHandler.glob(projectPath, glob: $0) }))
                } else if type == "exclude" {
                    excluded.append(contentsOf: paths.flatMap({ context.fileHandler.glob(projectPath, glob: $0) }))
                } else {
                    let message = "Buildfile type \(type) not supported"
                    throw GraphLoadingError.unexpected(message)
                }
            }
            let includedSet = Set(included)
            let excludedSet = Set(excluded)
            files = includedSet.subtracting(excludedSet)
        } else {
            files = Set()
        }
    }
}

// MARK: - BuildFiles (Equatable)

extension BuildFiles: Equatable {
    /// Compares two build files.
    ///
    /// - Parameters:
    ///   - lhs: first build file to be compared.
    ///   - rhs: second build file to be compared.
    /// - Returns: true if the two objects  are  the same.
    static func == (lhs: BuildFiles, rhs: BuildFiles) -> Bool {
        return lhs.files == rhs.files
    }
}
