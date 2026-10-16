import FileSystem
import FileSystemTesting
import Foundation
import Testing
@testable import TuistREAPI

struct REAPIChunkingTests {
    /// Chunk lengths the `fastcdc` crate's v2020 chunker (3.2.1) cuts with 128 KiB / 512 KiB / 2 MiB at
    /// normalization level 2, the parameters the cache plugin and Kura use.
    @Test(.inTemporaryDirectory) func cutsTheChunksOfTheReferenceImplementation() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let cases: [(data: Data, lengths: [Int64])] = [
            (Data.splitMix(count: 20 * 1024 * 1024 + 12345, seed: 42), [
                200_872, 839_691, 648_557, 585_148, 614_689, 554_800, 849_313, 545_977, 544_832, 576_099, 249_243,
                584_310, 591_856, 546_307, 658_565, 558_347, 625_180, 383_301, 632_257, 635_654, 576_018, 568_533,
                630_545, 550_943, 392_388, 381_920, 926_450, 548_864, 572_565, 678_260, 570_720, 769_642, 465_822,
                623_777, 666_730, 561_950, 73740,
            ]),
            (Data(count: 5 * 1024 * 1024 + 7), [2_097_152, 2_097_152, 1_048_583]),
            (Data.splitMix(count: 100_000, seed: 7), [100_000]),
        ]
        for (index, testCase) in cases.enumerated() {
            let file = directory.appending(component: "\(index)").url
            try testCase.data.write(to: file)
            let chunks = try REAPIChunking.chunks(of: file, digest: REAPI.digest(testCase.data))
            #expect(chunks.map(\.digest.sizeBytes) == testCase.lengths)
            for chunk in chunks {
                let range = Int(chunk.offset) ..< Int(chunk.offset + chunk.digest.sizeBytes)
                #expect(chunk.digest == REAPI.digest(testCase.data.subdata(in: range)))
            }
        }
    }

    @Test(.inTemporaryDirectory) func rejectsAFileThatNoLongerMatchesItsDigest() throws {
        let file = try #require(FileSystem.temporaryTestDirectory).appending(component: "blob").url
        let data = Data.splitMix(count: 3 * 1024 * 1024, seed: 1)
        try data.write(to: file)
        var changed = data
        changed[0] ^= 1
        #expect(throws: REAPICacheError.corruptBlob) {
            try REAPIChunking.chunks(of: file, digest: REAPI.digest(changed))
        }
    }
}

extension Data {
    /// Deterministic bytes from the SplitMix64 generator, matching the generator the reference vectors were made with.
    static func splitMix(count: Int, seed: UInt64) -> Data {
        var state = seed
        var data = Data(capacity: count + 8)
        while data.count < count {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            Swift.withUnsafeBytes(of: (value ^ (value >> 31)).littleEndian) { data.append(contentsOf: $0) }
        }
        return data.prefix(count)
    }
}
