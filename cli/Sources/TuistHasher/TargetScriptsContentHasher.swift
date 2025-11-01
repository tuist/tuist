import Foundation
import Logging
import Mockable
import Path
import TuistCore
import TuistSupport
import XcodeGraph

@Mockable
public protocol TargetScriptsContentHashing {
    func hash(targetScripts: [TargetScript], sourceRootPath: AbsolutePath) async throws -> String
}

/// `TargetScriptsContentHasher`
/// is responsible for computing a unique hash that identifies a list of target scripts
public struct TargetScriptsContentHasher: TargetScriptsContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - TargetScriptsContentHashing

    /// Returns the hash that uniquely identifies an array of target scripts
    /// The hash takes into consideration the content of the script to execute, the content of input/output files, the name of the
    /// tool to execute, the order, the arguments and its name
    public func hash(targetScripts: [TargetScript], sourceRootPath: AbsolutePath) async throws -> String {
        var stringsToHash: [String] = []
        for script in targetScripts {
            var pathsToHash: [AbsolutePath] = []
            script.path.map { pathsToHash.append($0) }

            var dynamicPaths = resolvePathStrings(script.inputPaths + script.inputFileListPaths, sourceRootPath: sourceRootPath)
                .sorted()
            if let dependencyFile = script.dependencyFile {
                dynamicPaths += [dependencyFile]
            }

            for path in dynamicPaths {
                if path.pathString.contains("$") {
                    stringsToHash.append(path.relative(to: sourceRootPath).pathString)
                    Logger.current.notice(
                        "The path of the file \'\(path.url.lastPathComponent)\' is hashed, not the content. Because it has a build variable."
                    )
                } else {
                    pathsToHash.append(path)
                }
            }
            stringsToHash.append(contentsOf: try await pathsToHash.concurrentMap {
                do {
                    return try await contentHasher.hash(path: $0)
                } catch FileHandlerError.fileNotFound {
                    return $0.relative(to: sourceRootPath).pathString
                }
            })
            stringsToHash.append(
                contentsOf: resolvePathStrings(script.outputPaths + script.outputFileListPaths, sourceRootPath: sourceRootPath)
                    .map { $0.relative(to: sourceRootPath).pathString }
            )

            stringsToHash.append(contentsOf: [
                script.name,
                script.tool ?? "",
                script.order.rawValue,
            ] + script.arguments)
        }
        return try contentHasher.hash(stringsToHash)
    }

    // MARK: - Private

    private func resolvePathStrings(_ pathStrings: [String], sourceRootPath: AbsolutePath) -> [AbsolutePath] {
        pathStrings.compactMap { pathString -> AbsolutePath? in
            // Replace $(SRCROOT) with sourceRootPath
            let resolvedPathString = pathString.replacingOccurrences(of: "$(SRCROOT)", with: sourceRootPath.pathString)

            // Try to create AbsolutePath directly first
            if let absolutePath = try? AbsolutePath(validating: resolvedPathString) {
                return absolutePath
            }

            // If that fails, treat as relative to sourceRootPath
            if let relativePath = try? RelativePath(validating: resolvedPathString) {
                return sourceRootPath.appending(relativePath)
            }

            return nil
        }
    }
}
