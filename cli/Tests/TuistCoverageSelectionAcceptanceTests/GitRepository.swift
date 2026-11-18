import Foundation
import Path

/// Builds each test's history: commits with a fixed identity, branches and merges.
struct GitRepository {
    let path: AbsolutePath

    @discardableResult
    func run(_ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "-C", path.pathString,
            "-c", "user.name=Tuist Acceptance Tests", "-c", "user.email=acceptance@tuist.dev",
            "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
        ] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw GitError.failed(arguments: arguments, output: text)
        }
        return text
    }

    func commitAll(_ message: String) throws {
        try run("add", "-A")
        try run("commit", "-q", "-m", message)
    }

    func head() throws -> String {
        try run("rev-parse", "HEAD")
    }

    /// Replaces the one occurrence of `old` in the file at `relativePath`.
    func edit(_ relativePath: String, replacing old: String, with new: String) throws {
        let url = path.appending(try RelativePath(validating: relativePath)).url
        let content = try String(contentsOf: url, encoding: .utf8)
        guard content.components(separatedBy: old).count == 2 else {
            throw GitError.editNotFound(path: relativePath, text: old)
        }
        try content.replacingOccurrences(of: old, with: new).write(to: url, atomically: true, encoding: .utf8)
    }

    enum GitError: Error, CustomStringConvertible {
        case failed(arguments: [String], output: String)
        case editNotFound(path: String, text: String)

        var description: String {
            switch self {
            case let .failed(arguments, output): "git \(arguments.joined(separator: " ")) failed: \(output)"
            case let .editNotFound(path, text): "\(path) doesn't contain \(text) exactly once"
            }
        }
    }
}
