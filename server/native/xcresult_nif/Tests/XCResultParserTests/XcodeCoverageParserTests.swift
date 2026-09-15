import Command
import FileSystem
import Foundation
import Path
import Testing
@testable import XCResultParser

/// Stands in for `xccov`: prints the canned report or archive depending on what it is asked
/// for, or fails the way the tool does on a bundle without coverage. Records the bundle path it
/// was handed, since xccov only accepts one that ends in `.xcresult`.
///
/// `@unchecked` because the recorded arguments are the only mutable state and every access to
/// them goes through `lock`.
private final class XccovStub: CommandRunning, @unchecked Sendable {
    let reportJSON: String?
    let archiveJSON: String?
    private let lock = NSLock()
    private var recorded: [String] = []

    var bundleArguments: [String] {
        lock.withLock { recorded }
    }

    init(reportJSON: String?, archiveJSON: String? = "{}") {
        self.reportJSON = reportJSON
        self.archiveJSON = archiveJSON
    }

    func run(
        arguments: [String],
        environment _: [String: String],
        workingDirectory _: AbsolutePath?
    ) -> AsyncThrowingStream<CommandEvent, any Error> {
        if let last = arguments.last { lock.withLock { recorded.append(last) } }
        let output = arguments.contains("--file-list") ? "/repo/A.swift\n/repo/B.swift\n"
            : arguments.contains("--archive") ? archiveJSON : reportJSON
        return AsyncThrowingStream { continuation in
            guard let output, reportJSON != nil else {
                continuation.finish(
                    throwing: CommandError.terminated(
                        1,
                        stderr: "Error Domain=XCCovErrorDomain Code=0 \"No coverage data in result bundle\"",
                        command: arguments
                    )
                )
                return
            }
            continuation.yield(.standardOutput(Array(output.utf8)))
            continuation.finish()
        }
    }
}

struct XcodeCoverageParserTests {
    private let fileSystem = FileSystem()

    private func report(_ targets: String) -> String {
        """
        {"coveredLines": 0, "executableLines": 0, "lineCoverage": 0, "targets": [\(targets)]}
        """
    }

    @Test
    func joinsTheReportAndTheArchiveIntoOneEntryPerFile() async throws {
        let add = "/private/tmp/repo/Sources/Calculator/Add.swift"
        let dependency = "/Users/me/DerivedData/SourcePackages/checkouts/Dep/Dep.swift"
        let file = """
        {"name": "Add.swift", "path": "\(add)", "coveredLines": 2, "executableLines": 3, "lineCoverage": 0.6,
         "functions": [{"name": "add(_:_:)", "lineNumber": 2, "executionCount": 4, "coveredLines": 2, "executableLines": 3, "lineCoverage": 0.6}]}
        """
        // The framework's file shows up again under the test bundle that links it.
        let json = report("""
        {"name": "Calculator", "coveredLines": 2, "executableLines": 3, "lineCoverage": 0.6, "buildProductPath": "/dd/Calculator", "files": [\(
            file
        )]},
        {"name": "CalculatorTests", "coveredLines": 3, "executableLines": 4, "lineCoverage": 0.7, "buildProductPath": "/dd/CalculatorTests.xctest/Contents/MacOS/CalculatorTests", "files": [\(
            file
        ),
          {"name": "Dep.swift", "path": "\(
              dependency
          )", "coveredLines": 1, "executableLines": 1, "lineCoverage": 1, "functions": []}]}
        """)
        let archive = """
        {"\(add)": [{"line": 1, "isExecutable": false},
                    {"line": 3, "isExecutable": true, "executionCount": 0},
                    {"line": 2, "isExecutable": true, "executionCount": 4, "subranges": [{"column": 3, "executionCount": 0, "length": 1}]},
                    {"line": 4, "isExecutable": true, "executionCount": 1}],
         "\(dependency)": [{"line": 7, "isExecutable": true, "executionCount": 2}]}
        """
        let subject = XcodeCoverageParser(commandRunner: XccovStub(reportJSON: json, archiveJSON: archive))
        let manifest = XcodeCoverageManifest(
            rootDirectories: ["/tmp/repo", "/private/tmp/repo/"],
            partial: false,
            files: [XcodeCoverageSourceFile(path: "Sources/Calculator/Add.swift", gitBlobId: "a1b2")]
        )

        let got = try #require(await subject.parse(
            resultBundlePath: try AbsolutePath(validating: "/run.xcresult"),
            manifest: manifest
        ))

        #expect(got.files == [
            XcodeCoverageFile(
                path: dependency,
                gitBlobId: nil,
                targets: ["CalculatorTests"],
                isTest: true,
                coveredLines: 1,
                executableLines: 1,
                lineNumbers: [7],
                executionCounts: [2],
                functions: []
            ),
            XcodeCoverageFile(
                path: "Sources/Calculator/Add.swift",
                gitBlobId: "a1b2",
                targets: ["Calculator"],
                coveredLines: 2,
                executableLines: 3,
                lineNumbers: [2, 3, 4],
                executionCounts: [4, 0, 1],
                functions: [
                    XcodeCoverageFunction(
                        name: "add(_:_:)",
                        lineNumber: 2,
                        executionCount: 4,
                        coveredLines: 2,
                        executableLines: 3
                    ),
                ]
            ),
        ])
    }

    @Test
    func classifiesTargetsByTheirInnermostBundle() {
        #expect(XcodeCoverageParser.isTestBundle("/dd/Debug/CalculatorTests.xctest/Contents/MacOS/CalculatorTests"))
        #expect(XcodeCoverageParser.isTestBundle("/dd/Debug-iphonesimulator/App.app/PlugIns/AppTests.xctest/AppTests"))
        #expect(!XcodeCoverageParser.isTestBundle("/dd/Debug-iphonesimulator/AppTests.xctest/Frameworks/Lib.framework/Lib"))
        #expect(!XcodeCoverageParser.isTestBundle("/dd/Debug/PackageFrameworks/Calculator.framework/Calculator"))
        #expect(!XcodeCoverageParser.isTestBundle("/dd/Debug/libCalculator.dylib"))
        #expect(!XcodeCoverageParser.isTestBundle(nil))
    }

    @Test
    func carriesThePartialFlagOver() async throws {
        let json = report("""
        {"name": "A", "coveredLines": 1, "executableLines": 1, "lineCoverage": 1, "buildProductPath": "/a",
         "files": [{"name": "F.swift", "path": "/repo/F.swift", "coveredLines": 1, "executableLines": 1, "lineCoverage": 1, "functions": []}]}
        """)
        let archive = #"{"/repo/F.swift": [{"line": 1, "isExecutable": true, "executionCount": 1}]}"#
        let subject = XcodeCoverageParser(commandRunner: XccovStub(reportJSON: json, archiveJSON: archive))

        let got = try #require(await subject.parse(
            resultBundlePath: try AbsolutePath(validating: "/run.xcresult"),
            manifest: XcodeCoverageManifest(rootDirectories: ["/repo"], partial: true, files: [])
        ))

        #expect(got.partial)
        #expect(got.files.map(\.path) == ["F.swift"])
    }

    @Test
    func handsXccovAPathWithTheXcresultExtension() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "xcode-coverage-parser-tests") { root in
            // xcodebuild's own layout for `-resultBundlePath run`: `run.xcresult` plus a `run` link to it.
            let bundle = root.appending(component: "run.xcresult")
            try await fileSystem.makeDirectory(at: bundle)
            let link = root.appending(component: "run")
            try await fileSystem.createSymbolicLink(from: link, to: bundle)
            let stub = XccovStub(reportJSON: report(""))
            let subject = XcodeCoverageParser(commandRunner: stub)

            #expect(try await subject.coveredFilePaths(resultBundlePath: link) == ["/repo/A.swift", "/repo/B.swift"])
            #expect(stub.bundleArguments.map { $0.hasSuffix(".xcresult") } == [true])

            // A bundle that really has no extension, the way the server extracts an upload, is
            // reached through a link that has one.
            let bare = root.appending(component: "bare")
            try await fileSystem.makeDirectory(at: bare)
            #expect(try await subject.coveredFilePaths(resultBundlePath: bare) != nil)
            #expect(stub.bundleArguments.last?.hasSuffix("bundle.xcresult") == true)
        }
    }

    @Test
    func reportsNothingForABundleWithoutCoverage() async throws {
        let subject = XcodeCoverageParser(commandRunner: XccovStub(reportJSON: nil))
        let bundle = try AbsolutePath(validating: "/run.xcresult")

        #expect(try await subject.coveredFilePaths(resultBundlePath: bundle) == nil)
        #expect(try await subject.parse(
            resultBundlePath: bundle,
            manifest: XcodeCoverageManifest(rootDirectories: [], partial: false, files: [])
        ) == nil)
    }
}
