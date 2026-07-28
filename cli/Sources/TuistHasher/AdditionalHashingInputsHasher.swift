import Command
import Foundation
import Mockable
import Path
import TuistCore
import TuistEnvironment
import TuistSupport
import XcodeGraph

@Mockable
public protocol AdditionalHashingInputsHashing {
    func hash(
        inputs: [TargetHashingInput],
        hashedPaths: [AbsolutePath: String],
        sourceRootPath: AbsolutePath
    ) async throws -> (hash: String?, hashedPaths: [AbsolutePath: String])
}

public struct AdditionalHashingInputsHasher: AdditionalHashingInputsHashing {
    private let contentHasher: ContentHashing
    private let commandRunner: CommandRunning
    private let environmentVariables: @Sendable () -> [String: String]

    public init(
        contentHasher: ContentHashing,
        commandRunner: CommandRunning = CommandRunner(),
        environmentVariables: @escaping @Sendable () -> [String: String] = {
            Environment.current.variables
        }
    ) {
        self.contentHasher = contentHasher
        self.commandRunner = commandRunner
        self.environmentVariables = environmentVariables
    }

    public func hash(
        inputs: [TargetHashingInput],
        hashedPaths: [AbsolutePath: String],
        sourceRootPath: AbsolutePath
    ) async throws -> (hash: String?, hashedPaths: [AbsolutePath: String]) {
        guard !inputs.isEmpty else {
            return (hash: nil, hashedPaths: hashedPaths)
        }

        var hashedPaths = hashedPaths
        var componentHashes: [String] = []

        for input in inputs {
            switch input {
            case let .path(path):
                let pathHash = try await hash(path: path, cachedHash: hashedPaths[path])
                hashedPaths[path] = pathHash
                let relativePath = path.relative(to: sourceRootPath).pathString
                componentHashes.append(try contentHasher.hash("path-\(relativePath)-content-\(pathHash)"))
            case let .string(value):
                componentHashes.append(try contentHasher.hash("string-\(value)"))
            case let .environmentVariable(name):
                let component =
                    if let value = environmentVariables()[name] {
                        "environment-variable-\(name)-value-\(value)"
                    } else {
                        "environment-variable-\(name)-missing"
                    }
                componentHashes.append(try contentHasher.hash(component))
            case let .script(script):
                let output = try await commandRunner.runAndCollectOutput(
                    arguments: ["/bin/sh", "-c", script],
                    workingDirectory: sourceRootPath
                )
                componentHashes.append(try contentHasher.hash("script-\(output.standardOutput)"))
            }
        }

        return (
            hash: try contentHasher.hash(componentHashes.sorted()),
            hashedPaths: hashedPaths
        )
    }

    private func hash(
        path: AbsolutePath,
        cachedHash: String?
    ) async throws -> String {
        if let cachedHash {
            return cachedHash
        }

        return try await contentHasher.hash(path: path)
    }
}
