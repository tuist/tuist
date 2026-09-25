import Foundation
import Testing
@testable import TuistKit

struct CoverageMappingTests {
    private func uleb(_ value: UInt64) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return bytes
    }

    private func little(_ value: some FixedWidthInteger) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    private func padded(_ bytes: [UInt8]) -> [UInt8] {
        bytes + Array(repeating: 0, count: (8 - bytes.count % 8) % 8)
    }

    /// One function in `/src/Math.swift`: its body on lines 1 to 6 counted by counter 0, and a
    /// branch on lines 3 to 4 counted by `counter 0 - counter 1`, followed by a gap.
    private func sections() -> (covmap: Data, covfun: Data) {
        let names = ["/src", "Math.swift"].flatMap { uleb(UInt64($0.utf8.count)) + Array($0.utf8) }
        let filenames = uleb(2) + uleb(UInt64(names.count)) + uleb(0) + names
        let covmap =
            padded(little(UInt32(0)) + little(UInt32(filenames.count)) + little(UInt32(0)) + little(UInt32(5)) + filenames)

        let mapping: [UInt8] = uleb(1) + uleb(1)
            + uleb(1) + uleb(0 << 2 | 1) + uleb(1 << 2 | 1)
            + uleb(3)
            + uleb(0 << 2 | 1) + uleb(1) + uleb(1) + uleb(5) + uleb(2)
            + uleb(0 << 2 | 2) + uleb(2) + uleb(5) + uleb(1) + uleb(6)
            + uleb(0 << 2 | 1) + uleb(1) + uleb(6) + uleb(0) + uleb(9 | 1 << 31)
        let covfun = padded(
            little(UInt64(7)) + little(UInt32(mapping.count)) + little(UInt64(11))
                + little(CoverageMapping.reference(of: Data(filenames))) + mapping
        )
        return (Data(covmap), Data(covfun))
    }

    @Test func decodesFilesFunctionsAndRegions() throws {
        let sections = sections()
        let mapping = try #require(CoverageMapping(covmap: sections.covmap, covfun: sections.covfun))

        #expect(mapping.files == ["/src", "/src/Math.swift"])
        #expect(mapping.functionIndex[.init(reference: 7, hash: 11)] == 0)
        #expect(mapping.functions[0].regions.map(\.region) == [
            .init(kind: .code, counter: .reference(0), lineStart: 1, columnStart: 1, lineEnd: 6, columnEnd: 2),
            .init(kind: .code, counter: .subtract(0), lineStart: 3, columnStart: 5, lineEnd: 4, columnEnd: 6),
            .init(kind: .gap, counter: .reference(0), lineStart: 4, columnStart: 6, lineEnd: 4, columnEnd: 9),
        ])
    }

    @Test func tellsTheLinesThatRanAsLLVMCovDoes() throws {
        let sections = sections()
        let mapping = try #require(CoverageMapping(covmap: sections.covmap, covfun: sections.covfun))

        // The branch never ran: both counters moved alike, which a list of the counters that
        // moved could not tell from a branch that did.
        #expect(mapping.lines(file: 1, counts: [0: [3, 3]]) == [1: 3, 2: 3, 3: 3, 4: 0, 5: 3, 6: 3])
        #expect(mapping.lines(file: 1, counts: [0: [3, 1]]) == [1: 3, 2: 3, 3: 3, 4: 2, 5: 3, 6: 3])
        #expect(mapping.lines(file: 1, counts: [:]) == [1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0])
        #expect(mapping.lines(file: 0, counts: [:]).isEmpty)
    }

    @Test func refusesWhatItCannotRead() {
        let sections = sections()
        #expect(CoverageMapping(covmap: sections.covmap, covfun: Data(sections.covfun.prefix(30))) == nil)
        #expect(CoverageMapping(covmap: Data(), covfun: sections.covfun) == nil)
    }

    @Test func trustsOnlyTheFilesLLVMCovAgreesOn() throws {
        let sections = sections()
        let mapping = try #require(CoverageMapping(covmap: sections.covmap, covfun: sections.covfun))
        var agreeing = TestCoverageEvidenceService.LCOVFunctionTable()
        for line in ["SF:/src/Math.swift", "DA:1,3", "DA:2,3", "DA:3,3", "DA:4,0", "DA:5,3", "DA:6,3"] {
            agreeing.read(Substring(line))
        }
        var differing = TestCoverageEvidenceService.LCOVFunctionTable()
        for line in ["SF:/src/Math.swift", "DA:1,3", "DA:2,3", "DA:3,3", "DA:4,3", "DA:5,3", "DA:6,3"] {
            differing.read(Substring(line))
        }
        let counts: [CoverageMapping.FunctionKey: [UInt64]] = [.init(reference: 7, hash: 11): [3, 3]]

        #expect(VerifiedCoverageMapping(mapping: mapping, report: agreeing, profileCounts: counts).verifiedFiles == [1])
        #expect(VerifiedCoverageMapping(mapping: mapping, report: differing, profileCounts: counts).verifiedFiles.isEmpty)
        #expect(VerifiedCoverageMapping(mapping: mapping, report: agreeing, profileCounts: [:]).verifiedFiles.isEmpty)
    }

    @Test func givesARecordTheLinesItsDeltasRan() throws {
        let sections = sections()
        let mapping = try #require(CoverageMapping(covmap: sections.covmap, covfun: sections.covfun))
        let output = CoverageObserverOutput(
            images: [0: .init(
                path: "/products/App",
                functionByCounter: [],
                functions: [.init(reference: 7, hash: 11, first: 4, count: 2)]
            )],
            records: []
        )
        let verified = ["/products/App": VerifiedCoverageMapping(mapping: mapping, verifiedFiles: [1])]
        func record(_ deltas: [Int: [UInt64]]) -> CoverageObserverOutput.Record {
            .init(kind: .xctest, overlapped: false, module: "", suite: "", name: "", counters: [0: [4, 5]], deltas: deltas)
        }

        #expect(output.lines(of: record([0: [2, 2]]), mappings: verified) == ["/src/Math.swift": IndexSet([1, 2, 3, 5, 6])])
        #expect(output.lines(of: record([:]), mappings: verified).isEmpty)
        #expect(output.lines(of: record([0: [2, 2]]), mappings: [
            "/products/App": VerifiedCoverageMapping(mapping: mapping, verifiedFiles: []),
        ]).isEmpty)
    }

    @Test func readsTheTextProfile() {
        let text = """
        :ir
        add
        # Func Hash:
        11
        # Num Counters:
        2
        # Counter Values:
        3
        1

        """
        #expect(TestCoverageEvidenceService.profileCounts(text: text) == [
            .init(reference: CoverageObserverOutput.nameReference("add"), hash: 11): [3, 1],
        ])
    }
}
