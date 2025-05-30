import ArgumentParser
import FileSystem
import FileSystemTesting
import Foundation
import Logging
import Noora
import Path
import Testing
import TuistSupport
import XcodeProj

/// It uses service-context, which uses task locals (from structured concurrency), to inject
/// instances of core utilities like logger to mock their behaviour for unit tests.
///
/// - Parameters:
///   - forwardLogs: When true, it forwards the logs through the standard output and error.
///   - closure: The closure that will be executed with the task-local context set.
// swiftlint:disable:next identifier_name
func _withMockedDependencies(forwardLogs: Bool = false, _ closure: () async throws -> Void)
    async throws
{
    let (logger, logHandler) = Logger.initTestingLogger(forwardLogs: forwardLogs)

    try await Logger.$current.withValue(logger) {
        try await Logger.$testingLogHandler.withValue(logHandler) {
            try await Noora.$current.withValue(NooraMock(terminal: Terminal(isInteractive: false))) {
                try await RecentPathsStore.$current.withValue(MockRecentPathsStoring()) {
                    try await AlertController.$current.withValue(AlertController()) {
                        try await closure()
                    }
                }
            }
        }
    }
}

public func withMockedDependencies(forwardLogs: Bool = false, _ closure: () async throws -> Void)
    async throws
{
    try await _withMockedDependencies(forwardLogs: forwardLogs, closure)
}

public enum TuistTest {
    @TaskLocal public static var fixtureDirectory: AbsolutePath?

    public static func run(_ command: (some AsyncParsableCommand).Type, _ arguments: [String] = [])
        async throws
    {
        if let mockEnvironment = Environment.mocked {
            mockEnvironment.processId = UUID().uuidString
        }

        let run = {
            var parsedCommand = try command.parse(arguments)
            try await parsedCommand.run()
        }
        if let mockEnvironment = Environment.mocked {
            mockEnvironment.processId = UUID().uuidString
        }
        try await run()
    }

    public static func expectFrameworkNotEmbedded(
        _ framework: String,
        by targetName: String,
        inXcodeProj xcodeprojPath: AbsolutePath,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)
        let targets = xcodeproj.pbxproj.projects.flatMap(\.targets)
        let target = try #require(targets.first(where: { $0.name == targetName }))

        let embededFrameworks = target.embedFrameworksBuildPhases()
            .filter { $0.dstSubfolderSpec == .frameworks }
            .flatMap { phase -> [PBXBuildFile] in
                return phase.files ?? []
            }
            .compactMap { (buildFile: PBXBuildFile) -> String? in
                return buildFile.file?.name
            }
            .filter { $0.contains(".framework") }

        if embededFrameworks.contains("\(framework).framework") {
            Issue.record(
                "Target \(targetName) embeds the framework \(framework)",
                sourceLocation: sourceLocation
            )
            return
        }
    }

    public static func expectLogs(
        _ expected: String,
        at level: Logger.Level = .warning,
        _ comparison: (Logger.Level, Logger.Level) -> Bool = { $0 >= $1 },
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let output = Logger.testingLogHandler.collected[level, comparison]
        let message = """
        The output:
        ===========
        \(output)

        Doesn't contain the expected:
        ===========
        \(expected)
        """
        #expect(output.contains(expected) == true, "\(message)", sourceLocation: sourceLocation)
    }

    public static func doesntExpectLogs(
        _ pattern: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let standardOutput = Logger.testingLogHandler.collected[.info, <=]

        let message = """
        The standard output:
        ===========
        \(standardOutput)

        Contains the not expected:
        ===========
        \(pattern)
        """

        #expect(
            standardOutput.contains(pattern) == false, "\(message)", sourceLocation: sourceLocation
        )
    }

    @discardableResult
    public static func createFiles(_ files: [String], content: String? = nil) async throws
        -> [AbsolutePath]
    {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let paths = try files.map { temporaryPath.appending(try RelativePath(validating: $0)) }

        for item in paths {
            if try await !fileSystem.exists(item.parentDirectory, isDirectory: true) {
                try await fileSystem.makeDirectory(at: item.parentDirectory)
            }
            if try await fileSystem.exists(item) {
                try await fileSystem.remove(item)
            }
            if let content {
                try await fileSystem.writeText(content, at: item)
            } else {
                try await fileSystem.touch(item)
            }
        }
        return paths
    }

    @discardableResult
    public static func makeDirectories(_ folders: [String]) async throws -> [AbsolutePath] {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let paths = try folders.map { temporaryPath.appending(try RelativePath(validating: $0)) }
        for path in paths {
            if try await !fileSystem.exists(path, isDirectory: true) {
                try await fileSystem.makeDirectory(at: path)
            }
        }
        return paths
    }
}

public struct TuistTestMockedDependenciesTrait: TestTrait, SuiteTrait, TestScoping {
    let forwardingLogs: Bool

    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await _withMockedDependencies(forwardLogs: forwardingLogs) {
            try await function()
        }
    }
}

extension Trait where Self == TuistTestMockedDependenciesTrait {
    public static func withMockedDependencies(forwardingLogs: Bool = false) -> Self {
        return Self(forwardingLogs: forwardingLogs)
    }
}
