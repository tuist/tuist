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
private final class XccovStub: @unchecked Sendable {
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

    func callAsFunction(_ arguments: [String]) async throws -> XCResultToolOutput {
        if let last = arguments.last { lock.withLock { recorded.append(last) } }
        let output = arguments.contains("--file-list") ? "/repo/A.swift\n/repo/B.swift\n"
            : arguments.contains("--archive") ? archiveJSON : reportJSON
        guard let output, reportJSON != nil else {
            return XCResultToolOutput(
                standardOutput: "",
                standardError: "Error Domain=XCCovErrorDomain Code=0 \"No coverage data in result bundle\"",
                succeeded: false
            )
        }
        return XCResultToolOutput(standardOutput: output, standardError: "", succeeded: true)
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
    func joinsTheReportAndTheArchiveForTheRepositorysOwnCode() async throws {
        let add = "/private/tmp/repo/Sources/Calculator/Add.swift"
        let tests = "/private/tmp/repo/Tests/CalculatorTests/CalculatorTests.swift"
        let checkout = "/private/tmp/repo/.build/checkouts/Dep/Sources/Dep.swift"
        let outside = "/Users/me/DerivedData/SourcePackages/checkouts/Other/Other.swift"
        let add_file = """
        {"name": "Add.swift", "path": "\(add)", "coveredLines": 2, "executableLines": 3, "lineCoverage": 0.6,
         "functions": [{"name": "add(_:_:)", "lineNumber": 2, "executionCount": 4, "coveredLines": 2, "executableLines": 3, "lineCoverage": 0.6}]}
        """
        let other = { (path: String) in
            """
            {"name": "F.swift", "path": "\(path)", "coveredLines": 1, "executableLines": 1, "lineCoverage": 1,
             "functions": [{"name": "f()", "lineNumber": 1, "executionCount": 1, "coveredLines": 1, "executableLines": 1, "lineCoverage": 1}]}
            """
        }
        // The framework's file shows up again under the test bundle that links it.
        let json = report("""
        {"name": "Calculator", "coveredLines": 2, "executableLines": 3, "lineCoverage": 0.6, "buildProductPath": "/dd/Calculator.framework/Calculator", "files": [\(
            add_file
        ), \(other(checkout)), \(other(outside))]},
        {"name": "CalculatorTests", "coveredLines": 3, "executableLines": 4, "lineCoverage": 0.7, "buildProductPath": "/dd/CalculatorTests.xctest/Contents/MacOS/CalculatorTests", "files": [\(
            add_file
        ), \(other(tests))]}
        """)
        let archive = """
        {"\(add)": [{"line": 1, "isExecutable": false},
                    {"line": 3, "isExecutable": true, "executionCount": 0},
                    {"line": 2, "isExecutable": true, "executionCount": 4, "subranges": [{"column": 3, "executionCount": 0, "length": 1}]},
                    {"line": 4, "isExecutable": true, "executionCount": 1}],
         "\(tests)": [{"line": 1, "isExecutable": true, "executionCount": 1}],
         "\(checkout)": [{"line": 1, "isExecutable": true, "executionCount": 1}],
         "\(outside)": [{"line": 1, "isExecutable": true, "executionCount": 1}]}
        """
        let subject = XcodeCoverageParser(execute: XccovStub(reportJSON: json, archiveJSON: archive).callAsFunction)
        let manifest = XcodeCoverageManifest(
            rootDirectories: ["/tmp/repo", "/private/tmp/repo/"],
            partial: false,
            files: [
                XcodeCoverageSourceFile(path: "Sources/Calculator/Add.swift", gitBlobId: "a1b2"),
                XcodeCoverageSourceFile(path: "Tests/CalculatorTests/CalculatorTests.swift", gitBlobId: "c3d4"),
            ]
        )

        let got = try #require(await subject.parse(
            resultBundlePath: try AbsolutePath(validating: "/run.xcresult"),
            manifest: manifest
        ))

        // Package checkouts, inside the repository or out, are not the repository's code; test code
        // keeps its counts only.
        #expect(got.files == [
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
            XcodeCoverageFile(
                path: "Tests/CalculatorTests/CalculatorTests.swift",
                gitBlobId: "c3d4",
                targets: ["CalculatorTests"],
                isTest: true,
                coveredLines: 1,
                executableLines: 1,
                lineNumbers: [],
                executionCounts: [],
                functions: []
            ),
        ])
    }

    @Test
    func leavesOutFilesGitIgnoresInsideTheRepository() {
        #expect(XcodeCoverageParser.isDependencyPath(".build/checkouts/Dep/Dep.swift"))
        #expect(XcodeCoverageParser.isDependencyPath("App/DerivedData/SourcePackages/checkouts/Dep/Dep.swift"))
        #expect(XcodeCoverageParser.isDependencyPath("Pods/Alamofire/Source/Session.swift"))
        #expect(!XcodeCoverageParser.isDependencyPath("Sources/Calculator/Add.swift"))
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
        let subject = XcodeCoverageParser(execute: XccovStub(reportJSON: json, archiveJSON: archive).callAsFunction)

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
            let subject = XcodeCoverageParser(execute: stub.callAsFunction)

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
        let subject = XcodeCoverageParser(execute: XccovStub(reportJSON: nil).callAsFunction)
        let bundle = try AbsolutePath(validating: "/run.xcresult")

        #expect(try await subject.coveredFilePaths(resultBundlePath: bundle) == nil)
        #expect(try await subject.parse(
            resultBundlePath: bundle,
            manifest: XcodeCoverageManifest(rootDirectories: [], partial: false, files: [])
        ) == nil)
    }
}

struct JSONStreamScannerTests {
    private func write(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func iteratesTheMembersOfAnObjectWithoutDecodingTheirValues() throws {
        let url = try write("""
        { "/a/b.swift" : [{"line": 1, "s": "}]\\"tricky"}], "empty": [], "n": 12 ,"last":{"k":[1,{"x":"]"}]}}
        """)
        var members: [(String, String)] = []
        try JSONStreamScanner.forEachMember(ofObjectAt: url) { key, value in
            members.append((key, String(decoding: value, as: UTF8.self)))
        }
        #expect(members.map(\.0) == ["/a/b.swift", "empty", "n", "last"])
        #expect(members[0].1 == #"[{"line": 1, "s": "}]\"tricky"}]"#)
        #expect(members[1].1 == "[]")
        #expect(members[2].1 == "12")
        #expect(members[3].1 == #"{"k":[1,{"x":"]"}]}"#)
    }

    @Test func iteratesTheElementsOfOneArrayAndSkipsTheRest() throws {
        let url = try write("""
        {"coveredLines": 3, "targets": [{"name": "A", "files": []}, {"name": "B"}], "trailing": "x"}
        """)
        struct Named: Decodable { let name: String }
        var names: [String] = []
        try JSONStreamScanner.forEachElement(ofArrayAt: "targets", in: url, chunkSize: 5) { element in
            names.append(try JSONDecoder().decode(Named.self, from: element).name)
        }
        #expect(names == ["A", "B"])
    }

    @Test func readsAcrossChunkBoundaries() throws {
        let value = String(repeating: "x", count: 5000)
        let url = try write("{\"k\": \"\(value)\", \"k2\": [\(Array(repeating: "1", count: 3000).joined(separator: ","))]}")
        var lengths: [Int] = []
        try JSONStreamScanner.forEachMember(ofObjectAt: url, chunkSize: 7) { _, value in lengths.append(value.count) }
        #expect(lengths == [value.count + 2, 3000 * 2 + 1])
    }
}
