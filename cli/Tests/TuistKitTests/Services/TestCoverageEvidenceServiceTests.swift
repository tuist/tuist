import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistConfig
import TuistEnvironment
import TuistProcess
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
            overlappedTests: [.init(module: "AppTests", suite: "SwiftTests", name: "overlaps()")]
        ))
    }

    @Test func namesAnXCTestTestAsTheResultBundleDoes() {
        #expect(TestCoverageEvidenceService.testName(xctestSelector: "testAdd") == "testAdd()")
        #expect(TestCoverageEvidenceService.testName(xctestSelector: "testAddAndReturnError:") == "testAdd()")
        #expect(TestCoverageEvidenceService.testName(xctestSelector: "testAddWithCompletionHandler:") == "testAdd()")
    }

    @Test func mapsTheReportsAndTheMappingsFilesBackThroughThePrefixMap() throws {
        var table = TestCoverageEvidenceService.LCOVFunctionTable()
        table.remap = { $0.replacingOccurrences(of: "/^src", with: "/checkout") }
        for line in ["SF:/^src/Math.swift", "FN:2,add", "DA:2,1", "end_of_record"] {
            table.read(Substring(line))
        }
        #expect(table.filesByFunction == ["add": ["/checkout/Math.swift"]])
        #expect(table.executableLines == ["/checkout/Math.swift": IndexSet([2])])

        let mapping = CoverageMapping(files: ["/^src/Math.swift", "/elsewhere/B.swift"], functions: [])
            .remappingFiles { $0.replacingOccurrences(of: "/^src", with: "/checkout") }
        #expect(mapping.files == ["/checkout/Math.swift", "/elsewhere/B.swift"])
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
        #expect(table.executableLines == ["/src/Math.swift": IndexSet([2])])
        #expect(table.coveredLines == ["/src/Math.swift": IndexSet([2])])
        for (line, kept) in [
            ("SF:/src/Math.swift", true),
            ("FN:2,add", true),
            ("FNDA:1,add", false),
            ("FNF:3", false),
            ("DA:2,1", true),
            ("LF:3", false),
            ("FN:", false),
        ] {
            #expect(TestCoverageEvidenceService.LCOVFunctionTable.reads(Array(line.utf8)) == kept)
        }
    }

    @Test func readsAReportWhereverItsChunksEnd() {
        let report = Array("SF:/src/Måth.swift\nFN:2,add\nFNDA:1,add\nDA:2,1\nDA:3,0\nend_of_record".utf8)
        var whole = TestCoverageEvidenceService.LCOVFunctionTable()
        whole.read(bytes: report)
        whole.finish()

        #expect(whole.filesByFunction == ["add": ["/src/Måth.swift"]])
        #expect(whole.executableLines == ["/src/Måth.swift": IndexSet([2, 3])])
        for split in 1 ..< report.count {
            var table = TestCoverageEvidenceService.LCOVFunctionTable()
            table.read(bytes: report[..<split])
            table.read(bytes: Data(report[split...]))
            table.finish()
            #expect(table.filesByFunction == whole.filesByFunction)
            #expect(table.executableLines == whole.executableLines)
            #expect(table.coveredLines == whole.coveredLines)
        }
    }

    @Test(.inTemporaryDirectory) func findsTheExportsReportOfAnImageThroughSymlinksForTheSameProfile() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let products = directory.appending(components: "Build", "Products", "Debug")
        let image = products.appending(components: "AppTests.xctest", "Contents", "MacOS", "AppTests")
        try FileManager.default.createDirectory(atPath: image.parentDirectory.pathString, withIntermediateDirectories: true)
        try Data().write(to: URL(fileURLWithPath: image.pathString))
        let link = directory.appending(component: "Products")
        try FileManager.default.createSymbolicLink(atPath: link.pathString, withDestinationPath: products.pathString)
        let profile = directory.appending(component: "Coverage.profdata")
        let report = directory.appending(component: "0.lcov")

        let reports = CoverageReports(directory: directory, profile: profile, reportsByProduct: [image.pathString: report])

        #expect(reports.report(ofImage: "\(link.pathString)/AppTests.xctest/Contents/MacOS/AppTests", profile: profile) == report)
        #expect(reports.report(ofImage: image.pathString, profile: directory.appending(component: "Other.profdata")) == nil)
        #expect(reports.report(ofImage: "/elsewhere/AppTests", profile: profile) == nil)
    }

    @Test(.inTemporaryDirectory) func readsTheExportsReportsAndTheProfilesNamesInsteadOfRunningLLVMCov() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let url = { (path: AbsolutePath) in URL(fileURLWithPath: path.pathString) }
        func u32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        func u64(_ value: UInt64) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        func string(_ value: String) -> Data { u32(UInt32(value.utf8.count)) + Data(value.utf8) }

        // The test process loaded the image through a symlink; the export names its real path.
        let products = directory.appending(components: "Build", "Products", "Debug")
        let image = products.appending(components: "AppTests.xctest", "Contents", "MacOS", "AppTests")
        try FileManager.default.createDirectory(atPath: image.parentDirectory.pathString, withIntermediateDirectories: true)
        try Data().write(to: url(image))
        let link = directory.appending(component: "Products")
        try FileManager.default.createSymbolicLink(atPath: link.pathString, withDestinationPath: products.pathString)

        // One function, `add`, owning both counters; the image's own names are empty, so only the
        // profile can name it.
        let process = directory.appending(components: "output", "4242")
        try FileManager.default.createDirectory(atPath: process.pathString, withIntermediateDirectories: true)
        let dataAddress: UInt64 = 0x1000, countersAddress: UInt64 = 0x2000
        var record = u64(CoverageObserverOutput.nameReference("add")) + u64(0)
            + u64(UInt64(bitPattern: Int64(countersAddress) - Int64(dataAddress)))
        record += Data(count: 24) + u32(2)
        try (record + Data(count: 64 - record.count)).write(to: url(process.appending(component: "0.data")))
        try Data().write(to: url(process.appending(component: "0.names")))
        try "0\t16\t\(dataAddress)\t\(countersAddress)\t\(link.pathString)/AppTests.xctest/Contents/MacOS/AppTests\n"
            .write(to: url(process.appending(component: "images.tsv")), atomically: true, encoding: .utf8)
        try (Data([1, 0, 1, 0]) + string("AppTests") + string("MathTests") + string("testAdd")
            + u32(1) + u32(0) + u32(1) + u32(0) + u64(1))
            .write(to: url(process.appending(component: "records.bin")))

        let derivedData = directory.appending(component: "DerivedData")
        let profile = derivedData.appending(components: "Build", "ProfileData", "Device", "Coverage.profdata")
        try FileManager.default.createDirectory(atPath: profile.parentDirectory.pathString, withIntermediateDirectories: true)
        try Data().write(to: url(profile))
        let reports = directory.appending(component: "reports")
        try FileManager.default.createDirectory(atPath: reports.pathString, withIntermediateDirectories: true)
        let report = reports.appending(component: "0.lcov")
        try "SF:/src/Math.swift\nFN:1,add\nDA:1,1\nend_of_record\n".write(to: url(report), atomically: true, encoding: .utf8)
        let bundle = directory.appending(component: "Run.xcresult")
        try FileManager.default.createDirectory(atPath: bundle.pathString, withIntermediateDirectories: true)

        let commandRunner = MockCommandRunning()
        given(commandRunner).run(arguments: .any, environment: .any, workingDirectory: .any).willProduce { arguments, _, _ in
            AsyncThrowingStream { continuation in
                if arguments.contains("llvm-profdata") {
                    continuation
                        .yield(.standardOutput(Array("add\n# Func Hash:\n0\n# Num Counters:\n2\n# Counter Values:\n1\n0\n".utf8)))
                }
                continuation.finish()
            }
        }

        let evidence = await TestCoverageEvidenceService(commandRunner: commandRunner).record(
            session: TestCoverageEvidenceSession(directory: directory.appending(component: "output"), environment: [:]),
            resultBundlePath: bundle,
            derivedDataDirectory: derivedData,
            reports: CoverageReports(directory: reports, profile: profile, reportsByProduct: [image.pathString: report])
        )

        #expect(evidence == TestCoverageEvidence(
            paths: ["/src/Math.swift"],
            scopes: [
                .init(kind: .target, module: "AppTests", suite: "", name: "", files: [0]),
                .init(kind: .test, module: "AppTests", suite: "MathTests", name: "testAdd()", files: [0]),
            ],
            status: .collected
        ))
        verify(commandRunner).run(arguments: .matching { $0.contains("llvm-cov") }, environment: .any, workingDirectory: .any)
            .called(0)
        #expect(!FileManager.default.fileExists(atPath: reports.pathString))
    }

    @Test func collectsOnlyWhereTheTestProcessesCanWriteToTheMac() {
        #expect(TestCoverageEvidencePlatform(destination: "platform=macOS,arch=arm64") == .macOS)
        #expect(TestCoverageEvidencePlatform(destination: "platform=iOS Simulator,name=iPhone 16") == .iOSSimulator)
        #expect(TestCoverageEvidencePlatform(destination: "platform=tvOS Simulator,name=Apple TV") == nil)
        #expect(TestCoverageEvidencePlatform(destination: "id=00008110-000A") == nil)
    }

    @Test(.withMockedEnvironment()) func collectsOnlyWhenTheRunUploadsCoverage() async {
        // Without the `COVERAGE` client flag.
        #expect(await TestCoverageEvidenceService().prepare(platform: .macOS, config: .test()) == nil)

        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        let noUpload = TuistConfig.Tuist.test(testInsights: TuistConfig.Tuist.TestInsights(coverage: .init(upload: false)))
        #expect(await TestCoverageEvidenceService().prepare(platform: .macOS, config: noUpload) == nil)
    }

    @Test(.inTemporaryDirectory) func saysWhenNoTestProcessRecordedEvidence() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let bundle = directory.appending(component: "Run.xcresult")
        let output = directory.appending(component: "output")
        try FileManager.default.createDirectory(atPath: bundle.pathString, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: output.pathString, withIntermediateDirectories: true)

        let evidence = await TestCoverageEvidenceService().record(
            session: TestCoverageEvidenceSession(directory: output, environment: [:]),
            resultBundlePath: bundle,
            derivedDataDirectory: nil,
            reports: nil
        )

        // No target links TestCoverageAttribution: the bundle still says the run asked.
        #expect(evidence == TestCoverageEvidence(paths: [], scopes: [], status: .notLinked))
        #expect(TestCoverageEvidence.read(fromResultBundle: URL(fileURLWithPath: bundle.pathString)) == evidence)
    }

    @Test(.inTemporaryDirectory) func saysWhenTheLinkedPackageStoppedRecording() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let bundle = directory.appending(component: "Run.xcresult")
        let output = directory.appending(component: "output")
        try FileManager.default.createDirectory(atPath: bundle.pathString, withIntermediateDirectories: true)
        // The process's directory, emptied of its records after a failure.
        try FileManager.default.createDirectory(
            atPath: output.appending(component: "4242").pathString,
            withIntermediateDirectories: true
        )
        let reports = directory.appending(component: "reports")
        try FileManager.default.createDirectory(atPath: reports.pathString, withIntermediateDirectories: true)

        let evidence = await TestCoverageEvidenceService().record(
            session: TestCoverageEvidenceSession(directory: output, environment: [:]),
            resultBundlePath: bundle,
            derivedDataDirectory: nil,
            reports: CoverageReports(
                directory: reports,
                profile: directory.appending(component: "Coverage.profdata"),
                reportsByProduct: [:]
            )
        )

        #expect(evidence == TestCoverageEvidence(paths: [], scopes: [], status: .failed))
        // The export's reports are the evidence's to remove, whatever it found.
        #expect(!FileManager.default.fileExists(atPath: reports.pathString))
    }

    @Test(.withMockedEnvironment()) func tellsTheTestProcessesWhereToRecord() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"

        let session = try #require(await TestCoverageEvidenceService().prepare(platform: .iOSSimulator, config: .test()))
        defer { try? FileManager.default.removeItem(atPath: session.directory.pathString) }

        // The test targets link TestCoverageAttribution: nothing is injected into the test hosts.
        #expect(session.environment == ["TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_DIR": session.directory.pathString])
        #expect(await TestCoverageEvidenceService().prepare(platform: nil, config: .test()) == nil)
    }
}
