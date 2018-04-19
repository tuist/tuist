import Basic
import Foundation

// MARK: - BuildFiles

class BuildFiles {
    let files: Set<AbsolutePath>

    init(files: Set<AbsolutePath> = Set()) {
        self.files = files
    }

    init(json: JSON, context: GraphLoaderContexting) throws {
        if case let JSON.array(buildFilesArray) = json {
            var included: [AbsolutePath] = []
            var excluded: [AbsolutePath] = []
            try buildFilesArray.forEach { buildFiles in
                let type: String = try buildFiles.get("type")
                let paths: [String] = try buildFiles.get("paths")
                if type == "include" {
                    included.append(contentsOf: paths.flatMap({ context.fileHandler.glob(context.path, glob: $0) }))
                } else if type == "exclude" {
                    excluded.append(contentsOf: paths.flatMap({ context.fileHandler.glob(context.path, glob: $0) }))
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
    static func == (lhs: BuildFiles, rhs: BuildFiles) -> Bool {
        return lhs.files == rhs.files
    }
}
