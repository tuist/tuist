import Command
import Foundation
import Path
import TuistSupport

struct PackageDescriptionContextProvider {
    private let commandRunner: CommandRunning
    private let encoder = JSONEncoder()

    init(commandRunner: CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    func arguments(packageManifestPath: AbsolutePath) async throws -> [String] {
        ["-context", try await encodedContext(packageManifestPath: packageManifestPath)]
    }

    func cacheHash(packageManifestPath: AbsolutePath, environment: [String: String]) async throws -> String? {
        var components = environment.map { "\($0.key)=\($0.value)" }
        components.append("context=\(try await encodedContext(packageManifestPath: packageManifestPath))")
        return components.sorted().joined(separator: "-").md5
    }

    private func encodedContext(packageManifestPath: AbsolutePath) async throws -> String {
        let context = PackageDescriptionContext(
            packageDirectory: packageManifestPath.parentDirectory.pathString,
            gitInformation: await gitInformation(at: packageManifestPath.parentDirectory)
        )
        let data = try encoder.encode(context)
        return String(decoding: data, as: UTF8.self)
    }

    private func gitInformation(at packageDirectory: AbsolutePath) async -> PackageDescriptionContext.GitInformation? {
        do {
            let currentCommit = try await commandRunner.run(arguments: [
                "git",
                "-C",
                packageDirectory.pathString,
                "rev-parse",
                "--verify",
                "HEAD",
            ])
            .concatenatedString()
            .trimmingCharacters(in: .whitespacesAndNewlines)

            let currentTag = try? await commandRunner.run(arguments: [
                "git",
                "-C",
                packageDirectory.pathString,
                "describe",
                "--exact-match",
                "--tags",
            ])
            .concatenatedString()
            .trimmingCharacters(in: .whitespacesAndNewlines)

            let status = try await commandRunner.run(arguments: [
                "git",
                "-C",
                packageDirectory.pathString,
                "status",
                "-s",
            ])
            .concatenatedString()

            return PackageDescriptionContext.GitInformation(
                currentTag: currentTag?.isEmpty == false ? currentTag : nil,
                currentCommit: currentCommit,
                hasUncommittedChanges: !status.isEmpty
            )
        } catch {
            return nil
        }
    }
}
