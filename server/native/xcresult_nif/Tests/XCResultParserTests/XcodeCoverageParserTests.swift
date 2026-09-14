import Command
import FileSystem
import Foundation
import Path
import Testing
@testable import XCResultParser

/// Stands in for `xccov`: writes the canned report to the redirect target the
/// parser reads back, or fails the way the tool does on a bundle without
/// coverage.
private struct XccovStub: CommandRunning {
    let reportJSON: String?

    func run(
        arguments: [String],
        environment _: [String: String],
        workingDirectory _: AbsolutePath?
    ) -> AsyncThrowingStream<CommandEvent, any Error> {
        let command = arguments.last ?? ""
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
            if let redirect = command.range(of: "> '") {
                let tail = command[redirect.upperBound...]
                if let close = tail.firstIndex(of: "'") {
                    try? reportJSON.write(toFile: String(tail[..<close]), atomically: true, encoding: .utf8)
                }
            }
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

        let got = try #require(await subject.parse(resultBundlePath: root.appending(component: "run.xcresult"), rootDirectory: nil))

        #expect(got.targets[0].files.map(\.path) == ["/repo/F.swift"])
        }
    }
}
