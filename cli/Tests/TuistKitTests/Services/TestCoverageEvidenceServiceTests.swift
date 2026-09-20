import Foundation
import Testing
import TuistTesting
import XCResultParser
@testable import TuistKit

struct TestCoverageEvidenceServiceTests {
    private func output(_ records: [CoverageObserverOutput.Record]) -> CoverageObserverOutput {
        CoverageObserverOutput(
            images: [0: .init(path: "/products/App", functionByCounter: ["add", "add", "sign", "bootstrap", nil])],
            records: records
        )
    }

    @Test func reducesCountersToFilesPerTestSuiteAndTarget() {
        let evidence = TestCoverageEvidenceService.reduce(
            outputs: [output([
                .init(kind: .gap, overlapped: false, module: "AppTests", suite: "MathTests", name: "", counters: [0: [3]]),
                .init(
                    kind: .xctest,
                    overlapped: false,
                    module: "AppTests",
                    suite: "MathTests",
                    name: "testAddAndReturnError:",
                    counters: [0: [0, 1]]
                ),
                .init(
                    kind: .swiftTesting,
                    overlapped: false,
                    module: "AppTests",
                    suite: "SwiftTests",
                    name: "signs(value:)",
                    counters: [0: [2]]
                ),
                .init(
                    kind: .swiftTesting,
                    overlapped: false,
                    module: "AppTests",
                    suite: "SwiftTests",
                    name: "signs(value:)",
                    counters: [0: [0, 4]]
                ),
                .init(
                    kind: .swiftTesting,
                    overlapped: true,
                    module: "AppTests",
                    suite: "SwiftTests",
                    name: "overlaps()",
                    counters: [0: [2]]
                ),
                .init(kind: .gap, overlapped: false, module: "AppTests", suite: "", name: "", counters: [0: [4]]),
            ])],
            filesByFunction: ["/products/App": [
                "add": ["/src/Math.swift"],
                "sign": ["/src/Sign.swift"],
                "bootstrap": ["/src/Boot.swift"],
            ]]
        )

        #expect(evidence == TestCoverageEvidence(
            paths: ["/src/Boot.swift", "/src/Math.swift", "/src/Sign.swift"],
            scopes: [
                .init(kind: .target, module: "AppTests", suite: "", name: "", files: [0, 1, 2]),
                .init(kind: .suite, module: "AppTests", suite: "MathTests", name: "", files: [0]),
                .init(kind: .test, module: "AppTests", suite: "MathTests", name: "testAdd()", files: [1]),
                .init(kind: .test, module: "AppTests", suite: "SwiftTests", name: "signs(value:)", files: [1, 2]),
            ],
            unattributedTests: 1
        ))
    }

    @Test func namesAnXCTestTestAsTheResultBundleDoes() {
        #expect(TestCoverageEvidenceService.testName(xctestSelector: "testAdd") == "testAdd()")
        #expect(TestCoverageEvidenceService.testName(xctestSelector: "testAddAndReturnError:") == "testAdd()")
        #expect(TestCoverageEvidenceService.testName(xctestSelector: "testAddWithCompletionHandler:") == "testAdd()")
    }

    @Test func readsFunctionsAndTheirFilesOffLCOV() {
        var table = TestCoverageEvidenceService.LCOVFunctionTable()
        for line in [
            "SF:/src/Math.swift",
            "FN:2,add",
            "FNDA:1,add",
            "DA:2,1",
            "end_of_record",
            "SF:/src/Shared.h",
            "FN:9,add",
            "FN:1,a,b",
        ] {
            table.read(Substring(line))
        }

        #expect(table.filesByFunction == ["add": ["/src/Math.swift", "/src/Shared.h"], "a,b": ["/src/Shared.h"]])
        for (line, kept) in [
            ("SF:/src/Math.swift", true),
            ("FN:2,add", true),
            ("FNDA:1,add", false),
            ("FNF:3", false),
            ("DA:2,1", false),
            ("FN:", false),
        ] {
            #expect(TestCoverageEvidenceService.LCOVFunctionTable.reads(Array(line.utf8)) == kept)
        }
    }

    @Test func onlyInjectsWhereTheObserverIsBuiltFor() {
        #expect(TestCoverageEvidencePlatform(destination: "platform=macOS,arch=arm64") == .macOS)
        #expect(TestCoverageEvidencePlatform(destination: "platform=iOS Simulator,name=iPhone 16") == .iOSSimulator)
        #expect(TestCoverageEvidencePlatform(destination: "platform=tvOS Simulator,name=Apple TV") == nil)
        #expect(TestCoverageEvidencePlatform(destination: "id=00008110-000A") == nil)
    }

    @Test(.withMockedEnvironment()) func collectsNothingUnlessAskedTo() async {
        #expect(await TestCoverageEvidenceService().prepare(platform: .macOS) == nil)
    }
}
