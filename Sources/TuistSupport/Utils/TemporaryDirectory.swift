import Foundation
import TSCBasic
import TSCLibc

/// A class to create disposable directories using POSIX's mkdtemp() method.
public final class TemporaryDirectory {
    /// If specified during init, the temporary directory name begins with this prefix.
    let prefix: String

    /// The full path of the temporary directory.
    public let path: AbsolutePath

    /// If true, try to remove the whole directory tree before deallocating.
    let shouldRemoveTreeOnDeinit: Bool

    /// Creates a temporary directory which is automatically removed when the object of this class goes out of scope.
    ///
    /// - Parameters:
    ///     - dir: If specified the temporary directory will be created in this directory otherwise environment
    ///            variables TMPDIR, TEMP and TMP will be checked for a value (in that order). If none of the env
    ///            variables are set, dir will be set to `/tmp/`.
    ///     - prefix: The prefix to the temporary file name.
    ///     - removeTreeOnDeinit: If enabled try to delete the whole directory tree otherwise remove only if its empty.
    ///
    /// - Throws: MakeDirectoryError
    public init(
        dir: AbsolutePath? = nil,
        prefix: String = "TemporaryDirectory",
        removeTreeOnDeinit: Bool = false
    ) throws {
        shouldRemoveTreeOnDeinit = removeTreeOnDeinit
        self.prefix = prefix
        // Construct path to the temporary directory.
        let path = try determineTempDirectory(dir).appending(RelativePath(prefix + ".XXXXXX"))

        // Convert path to a C style string terminating with null char to be an valid input
        // to mkdtemp method. The XXXXXX in this string will be replaced by a random string
        // which will be the actual path to the temporary directory.
        var template = [UInt8](path.pathString.utf8).map { Int8($0) } + [Int8(0)]

        if TSCLibc.mkdtemp(&template) == nil {
            throw MakeDirectoryError.other(errno)
        }

        self.path = try AbsolutePath(validating: String(cString: template))
    }

    /// Remove the temporary file before deallocating.
    deinit {
        if shouldRemoveTreeOnDeinit {
            _ = try? FileManager.default.removeItem(atPath: path.pathString)
        }
    }
}
