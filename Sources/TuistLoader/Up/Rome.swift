import Foundation
import TSCBasic
import TuistCore
import TuistSupport

/// Protocol that defines an interface to interact with a local Rome setup.
protocol Romeaging {
    /// Retrieves the dependencies in the given directory.
    ///
    /// - Parameters:
    ///   - path: Directory where the Carthage dependencies are defined.
    ///   - platforms: Platforms the dependencies will be updated for.
    ///   - cachePrefix: Cache Prefix to use when downloading dependencies
    /// - Throws: An error if the dependencies download fails.
    func download(path: AbsolutePath, platforms: [Platform], cachePrefix: String?) throws
}

final class Rome: Romeaging {
    /// Retrieves the dependencies in the given directory.
    ///
    /// - Parameters:
    ///   - path: Directory where the Carthage dependencies are defined.
    ///   - platforms: Platforms the dependencies will be updated for.
    ///   - cachePrefix: Cache Prefix to use when downloading dependencies
    /// - Throws: An error if the dependencies update fails.
    func download(path: AbsolutePath, platforms: [Platform], cachePrefix: String?) throws {
        let romePath = try System.shared.which("rome")

        var command: [String] = [romePath]
        command.append("download")

        if let cachePrefix = cachePrefix {
            command.append("--cache-prefix")
            command.append(cachePrefix)
        }

        if !platforms.isEmpty {
            command.append("--platform")
            command.append(platforms.map { $0.caseValue }.joined(separator: ","))
        }

        try System.shared.run(command)
    }
}

