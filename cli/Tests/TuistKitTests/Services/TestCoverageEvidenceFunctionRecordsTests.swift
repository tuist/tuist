import Foundation
import Testing
import XCResultParser
@testable import TuistKit

/// Swift Testing tests that ran in parallel, attributed through the functions their tasks entered.
struct TestCoverageEvidenceFunctionRecordsTests {
    /// Swift Testing tests that overlapped take their files from what their tasks entered, with the
    /// process's floor and what the counters saw run that function tracking didn't.
    @Test func attributesOverlappingSwiftTestingTestsThroughTheFunctionsTheirTasksEntered() {
        var process = CoverageObserverOutput(
            images: [0: .init(path: "/products/AppTests", functionByCounter: ["add", "sign", "boot", "dynamic"])],
            records: [
                .init(
                    kind: .xctest,
                    overlapped: false,
                    module: "AppTests",
                    suite: "Legacy",
                    name: "testBoot",
                    counters: [0: [2]]
                ),
                .init(
                    kind: .swiftTesting,
                    overlapped: true,
                    module: "AppTests",
                    suite: "Math",
                    name: "adds()",
                    counters: [0: [0, 1]]
                ),
                .init(
                    kind: .swiftTesting,
                    overlapped: true,
                    module: "AppTests",
                    suite: "Math",
                    name: "signs()",
                    counters: [0: [1, 3]]
                ),
                .init(kind: .gap, overlapped: false, module: "AppTests", suite: "", name: "", counters: [0: [3]]),
            ]
        )
        process.functionImages = [0: "/products/AppTests"]
        process.functionRecords = [
            .init(floor: false, module: "AppTests", suite: "Math", name: "adds()", offsets: [0: [0x100, 0x108]]),
            .init(floor: false, module: "AppTests", suite: "Math", name: "signs()", offsets: [0: [0x200]]),
            .init(floor: true, module: "", suite: "", name: "", offsets: [0: [0x300]]),
        ]
        // `$s3App4bootyyFTY0_` has no symbol: it's the continuation of the async function before it.
        let symbols = ImageSymbols(starts: [0x100, 0x200, 0x300], names: ["$s3App3addyyF", "$s3App4signyyF", "$s3App4bootyyF"])

        let evidence = TestCoverageEvidenceService.reduce(
            outputs: [process],
            filesByFunction: ["/products/AppTests": [
                "add": ["/src/Add.swift"],
                "sign": ["/src/Sign.swift"],
                "boot": ["/src/Boot.swift"],
                "dynamic": ["/src/Dynamic.swift"],
                "$s3App3addyyF": ["/src/Add.swift"],
                "Sources/Sign.swift:$s3App4signyyF": ["/src/Sign.swift"],
                "$s3App4bootyyF": ["/src/Boot.swift"],
            ]],
            symbols: ["/products/AppTests": symbols]
        )

        #expect(evidence.overlappedTests.isEmpty)
        let files = Dictionary(uniqueKeysWithValues: evidence.scopes.filter { $0.kind == .test }.map {
            ($0.name, Set($0.files.map { evidence.paths[$0] }))
        })
        // The floor (Boot, run by a GCD queue) and Dynamic, which the counters saw run among the Swift
        // Testing tests but no function record names, count for both; the XCTest test keeps its own.
        #expect(files == [
            "testBoot()": ["/src/Boot.swift"],
            "adds()": ["/src/Add.swift", "/src/Boot.swift", "/src/Dynamic.swift"],
            "signs()": ["/src/Sign.swift", "/src/Boot.swift", "/src/Dynamic.swift"],
        ])
        #expect(evidence.scopes.filter { $0.kind == .test && $0.name != "testBoot()" }.allSatisfy { $0.lines == nil })
    }

    /// A function record naming an image without symbols can't be told, so the process's overlapping
    /// tests stay overlapped rather than miss what they ran.
    @Test func leavesOverlappingTestsOverlappedWhenAFunctionCannotBeTold() {
        var process = CoverageObserverOutput(
            images: [0: .init(path: "/products/AppTests", functionByCounter: ["add"])],
            records: [
                .init(
                    kind: .swiftTesting,
                    overlapped: true,
                    module: "AppTests",
                    suite: "Math",
                    name: "adds()",
                    counters: [0: [0]]
                ),
            ]
        )
        process.functionImages = [0: "/products/AppTests"]
        process.functionRecords = [.init(floor: false, module: "AppTests", suite: "Math", name: "adds()", offsets: [0: [0x100]])]

        let evidence = TestCoverageEvidenceService.reduce(
            outputs: [process],
            filesByFunction: ["/products/AppTests": ["add": ["/src/Add.swift"]]],
            symbols: [:]
        )

        #expect(evidence.overlappedTests == [.init(module: "AppTests", suite: "Math", name: "adds()")])
        #expect(!evidence.scopes.contains { $0.kind == .test })
    }

    @Test func readsFunctionRecords() {
        var data = Data()
        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append(_ string: String) {
            append(UInt32(string.utf8.count))
            data.append(contentsOf: Array(string.utf8))
        }
        data.append(contentsOf: [3, 2, 1, 0])
        append(""); append(""); append("")
        append(1); append(0); append(2); append(0x10); append(0x20)
        data.append(contentsOf: [3, 0, 1, 0])
        append("AppTests"); append("Math"); append("adds()")
        append(1); append(1); append(1); append(0x30)
        // Cut off mid-record.
        data.append(contentsOf: [3, 0, 1])

        #expect(CoverageObserverOutput.parseFunctionRecords(data) == [
            .init(floor: true, module: "", suite: "", name: "", offsets: [0: [0x10, 0x20]]),
            .init(floor: false, module: "AppTests", suite: "Math", name: "adds()", offsets: [1: [0x30]]),
        ])
        #expect(CoverageObserverOutput.parseFunctionImages("0\t12\t/products/A\n1\t4\t/products/B\n") == [
            0: "/products/A", 1: "/products/B",
        ])
    }
}
