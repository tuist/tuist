import Basic
import Foundation
import TuistCore

protocol BuildCopying: AnyObject {
    func copy(from: AbsolutePath, to: AbsolutePath) throws
}

class BuildCopier: BuildCopying {
    // MARK: - Static

    /// Files that should be copied (if they exist).
    static let files: [String] = [
        "tuist",
        // Project description
        "ProjectDescription.swiftmodule",
        "ProjectDescription.swiftdoc",
        "libProjectDescription.dylib",
    ]

    // MARK: - Attributes

    private let fileHandler: FileHandling
    private let system: Systeming

    // MARK: - Init

    init(fileHandler: FileHandling = FileHandler(),
         system: Systeming = System()) {
        self.fileHandler = fileHandler
        self.system = system
    }

    func copy(from: AbsolutePath, to: AbsolutePath) throws {
        try BuildCopier.files.forEach { file in
            let filePath = from.appending(component: file)
            let toPath = to.appending(component: file)
            if !fileHandler.exists(filePath) { return }
            try system.run("/bin/cp", "-rf", filePath.pathString, toPath.pathString)
            if file == "tuist" {
                try system.run("/bin/chmod", "+x", toPath.pathString)
            }
        }
    }
}
