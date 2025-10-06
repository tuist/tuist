import FileSystem
import Foundation
import Logging
import Mockable
import Path
import TuistCore
import XcodeGraph

@Mockable
public protocol TargetScriptsContentHashing {
    func hash(targetScripts: [TargetScript], sourceRootPath: AbsolutePath) async throws -> String
}

/// `TargetScriptsContentHasher`
/// is responsible for computing a unique hash that identifies a list of target scripts
public struct TargetScriptsContentHasher: TargetScriptsContentHashing {
    private let contentHasher: ContentHashing
    private let fileSystem: FileSysteming

    // MARK: - Init

    public init(
        contentHasher: ContentHashing,
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.contentHasher = contentHasher
        self.fileSystem = fileSystem
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

            var dynamicPaths = script.inputPaths
                .compactMap { try? AbsolutePath(validating: $0) }
                .sorted()

            let fileListPaths = script.inputFileListPaths
                .compactMap { try? AbsolutePath(validating: $0) }
                .sorted()

            for fileListPath in fileListPaths {
                await processInputFileListPath(
                    fileListPath,
                    sourceRootPath: sourceRootPath,
                    pathsToHash: &pathsToHash,
                    stringsToHash: &stringsToHash
                )
            }

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
            stringsToHash.append(contentsOf: try await pathsToHash.concurrentMap { try await contentHasher.hash(path: $0) })
            stringsToHash.append(
                contentsOf: (script.outputPaths + script.outputFileListPaths)
                    .compactMap { try? AbsolutePath(validating: $0) }
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

    private func processInputFileListPath(
        _ fileListPath: AbsolutePath,
        sourceRootPath: AbsolutePath,
        pathsToHash: inout [AbsolutePath],
        stringsToHash: inout [String]
    ) async {
        if fileListPath.pathString.contains("$") {
            stringsToHash.append(fileListPath.relative(to: sourceRootPath).pathString)
            Logger.current.notice(
                "The path of the file \'\(fileListPath.url.lastPathComponent)\' is hashed, not the content. Because it has a build variable."
            )
        } else if fileListPath.extension == "xcfilelist" {
            await processXCFileList(
                fileListPath,
                sourceRootPath: sourceRootPath,
                pathsToHash: &pathsToHash,
                stringsToHash: &stringsToHash
            )
        } else {
            pathsToHash.append(fileListPath)
        }
    }

    private func processXCFileList(
        _ fileListPath: AbsolutePath,
        sourceRootPath: AbsolutePath,
        pathsToHash: inout [AbsolutePath],
        stringsToHash: inout [String]
    ) async {
        do {
            let fileListContent = try await fileSystem.readTextFile(at: fileListPath)
            let pathStrings = fileListContent
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }

            for pathString in pathStrings {
                if pathString.contains("$") {
                    stringsToHash.append(pathString)
                    Logger.current.notice(
                        "The path '\(pathString)' is hashed, not the content. Because it has a build variable."
                    )
                } else if let absolutePath = try? AbsolutePath(validating: pathString) {
                    pathsToHash.append(absolutePath)
                } else {
                    let resolvedPath = sourceRootPath.appending(try RelativePath(validating: pathString))
                    pathsToHash.append(resolvedPath)
                }
            }
        } catch {
            Logger.current.warning(
                "Failed to read .xcfilelist file at \'\(fileListPath.pathString)\': \(error). Hashing the file list path instead."
            )
            pathsToHash.append(fileListPath)
        }
    }
}
