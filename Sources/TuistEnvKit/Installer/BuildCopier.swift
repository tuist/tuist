import Basic
import Foundation
import TuistCore

protocol BuildCopying: AnyObject {
    /// Copies the frameworks under the project's Framework directory to the installation directory.
    ///
    /// - Parameters:
    ///   - from: Absolute path to the project's Framework folder.
    ///   - to: Installation directory where the binaries are.
    /// - Throws: An error if the copy of the frameworks fails.
    func copyFrameworks(from: AbsolutePath, to: AbsolutePath) throws

    /// Copies the frameworks under the project's Framework directory to the installation directory.
    ///
    /// - Parameters:
    ///   - from: Absolute path to the project's Framework folder.
    ///   - to: Installation directory where the binaries are.
    /// - Throws: An error if the copy of the frameworks fails.
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

    /// Instance to interact with the file system.
    private let fileHandler: FileHandling

    /// Instance to run system tasks.
    private let system: Systeming

    // MARK: - Init

    /// Initializes the build copier with its attributes.
    ///
    /// - Parameters:
    ///   - fileHandler: <#fileHandler description#>
    ///   - system: <#system description#>
    init(fileHandler: FileHandling = FileHandler(),
         system: Systeming = System()) {
        self.fileHandler = fileHandler
        self.system = system
    }

    /// Copies the built arfifacts that are required to run Tuist.
    ///
    /// - Parameters:
    ///   - from: Directory where all the artifacts have been built into (.build/release)
    ///   - to: Installation directory.
    /// - Throws: An error if a required artifact hasn't been found or the copy task fails.
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

    /// Copies the frameworks under the project's Framework directory to the installation directory.
    ///
    /// - Parameters:
    ///   - from: Absolute path to the project's Framework folder.
    ///   - to: Installation directory where the binaries are.
    /// - Throws: An error if the copy of the frameworks fails.
    func copyFrameworks(from: AbsolutePath, to: AbsolutePath) throws {
        let frameworks = ["Sentry.framework"]
        try frameworks.map { from.appending(component: $0) }.forEach { frameworkPath in

            /// We might use tuistenv to install older versions of Tuist that might
            /// not have all the frameworks listed here. For that reason, we can't
            /// require the framework to be present.
            if !fileHandler.exists(frameworkPath) { return }

            let toPath = to.appending(component: frameworkPath.components.last!)
            try system.run("/bin/cp", "-rf", frameworkPath.pathString, toPath.pathString)
        }
    }
}
