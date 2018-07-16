import Basic
import Foundation
import xpmcore

/// It defines the interface of an object that can copy the xpm build artifacts
/// into a destination folder filtering out the files that are not required.
protocol BuildCopying: AnyObject {
    /// Copies the build artifacts.
    ///
    /// - Parameters:
    ///   - from: folder where the build artifacts are (e.g. .build/release)
    ///   - to: folder where the build files should be copied into.
    /// - Throws: an error if the copying fails.
    func copy(from: AbsolutePath, to: AbsolutePath) throws
}

class BuildCopier: BuildCopying {

    // MARK: - Static

    /// Files that should be copied (if they exist).
    static let files: [String] = [
        "xpm",
        "xpmembed",
        // Project description
        "ProjectDescription.swiftmodule",
        "ProjectDescription.swiftdoc",
        "libProjectDescription.dylib",
    ]

    // MARK: - Attributes

    /// File handler.
    private let fileHandler: FileHandling

    /// Initializes the build copier with its attributes.
    ///
    /// - Parameter fileHandler: file handler.
    init(fileHandler: FileHandling = FileHandler()) {
        self.fileHandler = fileHandler
    }

    /// Copies the build artifacts.
    ///
    /// - Parameters:
    ///   - from: folder where the build artifacts are (e.g. .build/release)
    ///   - to: folder where the build files should be copied into.
    /// - Throws: an error if the copying fails.
    func copy(from: AbsolutePath, to: AbsolutePath) throws {
        try BuildCopier.files.forEach { file in
            let filePath = from.appending(component: file)
            let toPath = to.appending(component: file)
            if !fileHandler.exists(filePath) { return }
            try fileHandler.copy(from: filePath, to: toPath)
        }
    }
}
