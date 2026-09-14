import Command
import FileSystem
import Foundation
import Path
import Testing
@testable import XCResultParser

/// Stands in for `xccov`: streams the canned report on stdout, or fails the
/// way the tool does on a bundle without coverage. Records the bundle path it
/// was handed, since xccov only accepts one that ends in `.xcresult`.
///
/// `@unchecked` because the recorded arguments are the only mutable state and
/// every access to them goes through `lock`.
private final class XccovStub: CommandRunning, @unchecked Sendable {
    let reportJSON: String?
    private let lock = NSLock()
    private var recorded: [String] = []

    var bundleArguments: [String] {
        lock.withLock { recorded }
    }

    init(reportJSON: String?) {
        self.reportJSON = reportJSON
    }

    func run(
        arguments: [String],
        environment _: [String: String],
        workingDirectory _: AbsolutePath?
    ) -> AsyncThrowingStream<CommandEvent, any Error> {
        if let last = arguments.last { lock.withLock { recorded.append(last) } }
        return AsyncThrowingStream { continuation in
            guard let reportJSON else {
                continuation.finish(
                    throwing: CommandError.terminated(
                        1,
                        stderr: "Error Domain=XCCovErrorDomain Code=0 \"No coverage data in result bundle\"",
                        command: arguments
                    )
                )
                return
            }
            continuation.yield(.standardOutput(Array(reportJSON.utf8)))
            continuation.finish()
        }
    }
}

struct XcodeCoverageParserTests {
    private let fileSystem = FileSystem()

    @Test
    func parsesTargetsAndRelativizesPathsUnderTheRoot() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "xcode-coverage-parser-tests") { root in
            let bundle = root.appending(component: "run.xcresult")
            let json = """
            {
              "coveredLines": 6, "executableLines": 13, "lineCoverage": 0.46,
              "targets": [
                {
                  "name": "Calculator", "coveredLines": 5, "executableLines": 11, "lineCoverage": 0.45,
                  "buildProductPath": "/dd/Calculator",
                  "files": [
                    {"name": "Add.swift", "path": "\(root.pathString)/Sources/Calculator/Add.swift",
                     "coveredLines": 5, "executableLines": 11, "lineCoverage": 0.45, "functions": []},
                    {"name": "Dep.swift", "path": "/elsewhere/Dep.swift",
                     "coveredLines": 1, "executableLines": 2, "lineCoverage": 0.5, "functions": []}
                  ]
                }
              ]
            }
            """
            let subject = XcodeCoverageParser(commandRunner: XccovStub(reportJSON: json))

            let got = try #require(await subject.parse(resultBundlePath: bundle, rootDirectory: root))

            #expect(got.targets.map(\.name) == ["Calculator"])
            #expect(got.targets[0].coveredLines == 5)
            #expect(got.targets[0].executableLines == 11)
            #expect(got.targets[0].files.map(\.path) == ["Sources/Calculator/Add.swift", "/elsewhere/Dep.swift"])
            #expect(got.targets[0].files.map(\.coveredLines) == [5, 1])
        }
    }

    @Test
    func handsXccovAPathWithTheXcresultExtension() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "xcode-coverage-parser-tests") { root in
            // xcodebuild's own layout for `-resultBundlePath run`: `run.xcresult` plus a `run` link to it.
            let bundle = root.appending(component: "run.xcresult")
            try await fileSystem.makeDirectory(at: bundle)
            let link = root.appending(component: "run")
            try await fileSystem.createSymbolicLink(from: link, to: bundle)
            let stub = XccovStub(reportJSON: """
            {"coveredLines": 0, "executableLines": 0, "lineCoverage": 0, "targets": []}
            """)
            let subject = XcodeCoverageParser(commandRunner: stub)

            _ = try await subject.parse(resultBundlePath: link, rootDirectory: root)
            #expect(stub.bundleArguments.map { $0.hasSuffix(".xcresult") } == [true])

            // A bundle that really has no extension is reached through a link that has one.
            let bare = root.appending(component: "bare")
            try await fileSystem.makeDirectory(at: bare)
            _ = try await subject.parse(resultBundlePath: bare, rootDirectory: root)
            #expect(stub.bundleArguments.last?.hasSuffix("bundle.xcresult") == true)
        }
    }

    @Test
    func relativizesThroughASymlinkedRoot() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "xcode-coverage-parser-tests") { directory in
            let real = directory.appending(component: "real")
            try await fileSystem.makeDirectory(at: real)
            let link = directory.appending(component: "link")
            try await fileSystem.createSymbolicLink(from: link, to: real)
            let json = """
            {"coveredLines": 1, "executableLines": 1, "lineCoverage": 1, "targets": [
              {"name": "A", "coveredLines": 1, "executableLines": 1, "lineCoverage": 1, "buildProductPath": "/a",
               "files": [{"name": "F.swift", "path": "\(real
                .pathString)/Sources/F.swift", "coveredLines": 1, "executableLines": 1, "lineCoverage": 1, "functions": []}]}
            ]}
            """
            let subject = XcodeCoverageParser(commandRunner: XccovStub(reportJSON: json))

            let got = try #require(await subject.parse(
                resultBundlePath: real.appending(component: "run.xcresult"),
                rootDirectory: link
            ))

            #expect(got.targets[0].files.map(\.path) == ["Sources/F.swift"])
        }
    }

    @Test
    func leavesRelativePathsAlone() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "xcode-coverage-parser-tests") { root in
            let json = """
            {"coveredLines": 1, "executableLines": 1, "lineCoverage": 1, "targets": [
              {"name": "A", "coveredLines": 1, "executableLines": 1, "lineCoverage": 1, "buildProductPath": "/a",
               "files": [{"name": "F.swift", "path": "Sources/F.swift", "coveredLines": 1, "executableLines": 1, "lineCoverage": 1, "functions": []}]}
            ]}
            """
            let subject = XcodeCoverageParser(commandRunner: XccovStub(reportJSON: json))

            let got = try #require(await subject.parse(
                resultBundlePath: root.appending(component: "run.xcresult"),
                rootDirectory: root
            ))

            #expect(got.targets[0].files.map(\.path) == ["Sources/F.swift"])
        }
    }

    @Test
    func returnsNilWhenTheBundleHasNoCoverage() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "xcode-coverage-parser-tests") { root in
            let subject = XcodeCoverageParser(commandRunner: XccovStub(reportJSON: nil))

            let got = try await subject.parse(resultBundlePath: root.appending(component: "run.xcresult"), rootDirectory: root)

            #expect(got == nil)
        }
    }

    @Test
    func keepsPathsAbsoluteWithoutARoot() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "xcode-coverage-parser-tests") { root in
            let json = """
            {"coveredLines": 1, "executableLines": 1, "lineCoverage": 1, "targets": [
              {"name": "A", "coveredLines": 1, "executableLines": 1, "lineCoverage": 1, "buildProductPath": "/a",
               "files": [{"name": "F.swift", "path": "/repo/F.swift", "coveredLines": 1, "executableLines": 1, "lineCoverage": 1, "functions": []}]}
            ]}
            """
            let subject = XcodeCoverageParser(commandRunner: XccovStub(reportJSON: json))

            let got = try #require(await subject.parse(
                resultBundlePath: root.appending(component: "run.xcresult"),
                rootDirectory: nil
            ))

            #expect(got.targets[0].files.map(\.path) == ["/repo/F.swift"])
        }
    }
}
