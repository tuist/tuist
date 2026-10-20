import FileSystem
import FileSystemTesting
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

    /// A 64-bit Mach-O image with one `__DATA` segment holding the named section and `payload`.
    private func image(section: String, payload: [UInt8]) -> Data {
        func name(_ value: String) -> [UInt8] { Array(value.utf8) + Array(repeating: 0, count: 16 - value.utf8.count) }
        let headerSize = 32, segmentSize = 72 + 80
        let offset = headerSize + segmentSize
        var bytes: [UInt8] = []
        bytes += little(UInt32(0xFEED_FACF)) + little(UInt32(0x0100_000C)) + little(UInt32(0)) + little(UInt32(6))
        bytes += little(UInt32(1)) + little(UInt32(segmentSize)) + little(UInt32(0)) + little(UInt32(0))
        bytes += little(UInt32(0x19)) + little(UInt32(segmentSize)) + name("__DATA")
        bytes += little(UInt64(0)) + little(UInt64(payload.count)) + little(UInt64(offset)) + little(UInt64(payload.count))
        bytes += little(UInt32(3)) + little(UInt32(3)) + little(UInt32(1)) + little(UInt32(0))
        bytes += name(section) + name("__DATA") + little(UInt64(0)) + little(UInt64(payload.count))
        bytes += little(UInt32(offset)) + little(UInt32(0)) + little(UInt32(0)) + little(UInt32(0)) + little(UInt32(0))
        bytes += little(UInt32(0)) + little(UInt32(0)) + little(UInt32(0))
        precondition(bytes.count == offset)
        return Data(bytes + payload)
    }

    /// A BSD `ar` archive of `members`, each header a fixed 60 bytes and each member padded to an even size.
    private func archive(members: [Data]) -> Data {
        func field(_ value: String, _ width: Int) -> [UInt8] {
            Array(value.utf8) + Array(repeating: UInt8(ascii: " "), count: width - value.utf8.count)
        }
        var bytes = Array("!<arch>\n".utf8)
        for member in members {
            bytes += field("member.o/", 16) + field("0", 12) + field("0", 6) + field("0", 6) + field("644", 8)
            bytes += field(String(member.count), 10) + [UInt8(ascii: "`"), UInt8(ascii: "\n")]
            bytes += Array(member)
            if member.count % 2 == 1 { bytes.append(UInt8(ascii: "\n")) }
        }
        return Data(bytes)
    }

    /// A universal (fat) file of `slices`, each tagged with its CPU type, laid out on 8-byte boundaries.
    private func universal(slices: [(cpu: UInt32, data: Data)]) -> Data {
        func big(_ value: UInt32) -> [UInt8] { withUnsafeBytes(of: value.bigEndian) { Array($0) } }
        var header = big(0xCAFE_BABE) + big(UInt32(slices.count))
        var body: [UInt8] = []
        var offset = 8 + slices.count * 20
        for slice in slices {
            header += big(slice.cpu) + big(0) + big(UInt32(offset)) + big(UInt32(slice.data.count)) + big(3)
            body += Array(slice.data) + Array(repeating: 0, count: (8 - slice.data.count % 8) % 8)
            offset += slice.data.count + (8 - slice.data.count % 8) % 8
        }
        return Data(header + body)
    }

    /// A universal file in the 64-bit layout with one arm64 slice whose header claims `size` at `offset`.
    private func universal64(offset: UInt64, size: UInt64, slice: Data) -> Data {
        func big(_ value: UInt32) -> [UInt8] { withUnsafeBytes(of: value.bigEndian) { Array($0) } }
        func big64(_ value: UInt64) -> [UInt8] { withUnsafeBytes(of: value.bigEndian) { Array($0) } }
        let header = big(0xCAFE_BABF) + big(1)
            + big(0x0100_000C) + big(0) + big64(offset) + big64(size) + big(3) + big(0)
        return Data(header + Array(slice))
    }

    @Test(.inTemporaryDirectory) func refusesAUniversalFileWhoseSliceDoesNotFit() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let instrumented = archive(members: [image(section: "__llvm_covmap", payload: [1, 2])])
        let headerSize: UInt64 = 40
        // The size the header claims does not fit an `Int`, runs past the file, or is empty: none of
        // them may trap, and none carries a mapping.
        let oversized = directory.appending(component: "oversized")
        let truncated = directory.appending(component: "truncated")
        let empty = directory.appending(component: "empty")
        let sound = directory.appending(component: "sound")
        try universal64(offset: headerSize, size: .max, slice: instrumented).write(to: URL(fileURLWithPath: oversized.pathString))
        try universal64(offset: headerSize, size: UInt64(instrumented.count) + 1, slice: instrumented)
            .write(to: URL(fileURLWithPath: truncated.pathString))
        try universal64(offset: headerSize, size: 0, slice: instrumented).write(to: URL(fileURLWithPath: empty.pathString))
        try universal64(offset: headerSize, size: UInt64(instrumented.count), slice: instrumented)
            .write(to: URL(fileURLWithPath: sound.pathString))

        #expect(!CoverageMapping.carriesMapping(path: oversized.pathString))
        #expect(!CoverageMapping.carriesMapping(path: truncated.pathString))
        #expect(!CoverageMapping.carriesMapping(path: empty.pathString))
        #expect(CoverageMapping.carriesMapping(path: sound.pathString))
    }

    @Test(.inTemporaryDirectory) func tellsWhetherAProductCarriesACoverageMapping() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let instrumented = directory.appending(component: "Instrumented")
        let plain = directory.appending(component: "Plain")
        let instrumentedArchive = directory.appending(component: "libInstrumented.a")
        let plainArchive = directory.appending(component: "libPlain.a")
        let text = directory.appending(component: "text")
        try image(section: "__llvm_covmap", payload: [1, 2, 3, 4]).write(to: URL(fileURLWithPath: instrumented.pathString))
        try image(section: "__const", payload: [1, 2, 3, 4]).write(to: URL(fileURLWithPath: plain.pathString))
        try archive(members: [image(section: "__const", payload: [1]), image(section: "__llvm_covmap", payload: [1, 2])])
            .write(to: URL(fileURLWithPath: instrumentedArchive.pathString))
        try archive(members: [image(section: "__const", payload: [1])]).write(to: URL(fileURLWithPath: plainArchive.pathString))
        try Data("not a binary at all, just some text".utf8).write(to: URL(fileURLWithPath: text.pathString))
        // A static framework built for two architectures: a universal file whose slices are archives.
        let instrumentedUniversalArchive = directory.appending(component: "InstrumentedStatic")
        let plainUniversalArchive = directory.appending(component: "PlainStatic")
        try universal(slices: [
            (cpu: 0x0100_0007, data: archive(members: [image(section: "__const", payload: [1])])),
            (cpu: 0x0100_000C, data: archive(members: [image(section: "__llvm_covmap", payload: [1, 2])])),
        ]).write(to: URL(fileURLWithPath: instrumentedUniversalArchive.pathString))
        try universal(slices: [
            (cpu: 0x0100_0007, data: archive(members: [image(section: "__const", payload: [1])])),
            (cpu: 0x0100_000C, data: archive(members: [image(section: "__const", payload: [1])])),
        ]).write(to: URL(fileURLWithPath: plainUniversalArchive.pathString))

        #expect(CoverageMapping.carriesMapping(path: instrumented.pathString))
        #expect(!CoverageMapping.carriesMapping(path: plain.pathString))
        #expect(CoverageMapping.carriesMapping(path: instrumentedArchive.pathString))
        #expect(!CoverageMapping.carriesMapping(path: plainArchive.pathString))
        #expect(CoverageMapping.carriesMapping(path: instrumentedUniversalArchive.pathString))
        #expect(!CoverageMapping.carriesMapping(path: plainUniversalArchive.pathString))
        #expect(!CoverageMapping.carriesMapping(path: text.pathString))
        #expect(!CoverageMapping.carriesMapping(path: directory.appending(component: "missing").pathString))
    }

    /// A module with nothing to count (only global initializers) gets no coverage mapping from a coverage
    /// build, but it still references the profile runtime.
    @Test(.inTemporaryDirectory) func tellsAnInstrumentedProductWithNothingToCountFromAPlainOne() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let codeless = directory.appending(component: "libCodeless.a")
        let plain = directory.appending(component: "libPlain.a")
        try archive(members: [image(section: "__text", payload: Array("___llvm_profile_runtime_user".utf8))])
            .write(to: URL(fileURLWithPath: codeless.pathString))
        try archive(members: [image(section: "__text", payload: [1, 2, 3])]).write(to: URL(fileURLWithPath: plain.pathString))

        #expect(!CoverageMapping.carriesMapping(path: codeless.pathString))
        #expect(CoverageMapping.isInstrumented(path: codeless.pathString))
        #expect(!CoverageMapping.isInstrumented(path: plain.pathString))
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
