import Command
import Foundation
import Path
import TuistEnvironment

public struct CommandOutput: Sendable {
    public var standardOutput: String
    public var standardError: String
}

extension CommandRunning {
    public func runAndWait(
        arguments: [String],
        environment: [String: String] = Environment.current.variables,
        workingDirectory: AbsolutePath? = nil
    ) async throws {
        for try await _ in run(arguments: arguments, environment: environment, workingDirectory: workingDirectory) {}
    }

    public func capture(
        arguments: [String],
        environment: [String: String] = Environment.current.variables,
        workingDirectory: AbsolutePath? = nil
    ) async throws -> String {
        try await runAndCollectOutput(
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory
        ).standardOutput
    }

    public func runAndPrint(
        arguments: [String],
        environment: [String: String] = Environment.current.variables,
        workingDirectory: AbsolutePath? = nil
    ) async throws {
        for try await event in run(arguments: arguments, environment: environment, workingDirectory: workingDirectory) {
            switch event {
            case let .standardOutput(bytes):
                FileHandle.standardOutput.write(Data(bytes))
            case let .standardError(bytes):
                FileHandle.standardError.write(Data(bytes))
            }
        }
    }

    public func runAndCollectOutput(
        arguments: [String],
        environment: [String: String] = Environment.current.variables,
        workingDirectory: AbsolutePath? = nil
    ) async throws -> CommandOutput {
        var standardOutput = ""
        var standardError = ""

        for try await event in run(arguments: arguments, environment: environment, workingDirectory: workingDirectory) {
            switch event {
            case let .standardOutput(bytes):
                standardOutput.append(String(decoding: bytes, as: UTF8.self))
            case let .standardError(bytes):
                standardError.append(String(decoding: bytes, as: UTF8.self))
            }
        }

        return CommandOutput(standardOutput: standardOutput, standardError: standardError)
    }

    public func which(_ name: String) async throws -> String {
        try await capture(arguments: ["/usr/bin/env", "which", name]).spm_chomp()
    }

    public func commandExists(_ name: String) async -> Bool {
        do {
            _ = try await which(name)
            return true
        } catch {
            return false
        }
    }
}
