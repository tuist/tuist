import Foundation
import Testing
@testable import TuistKit

struct CoverageObserverOutputTests {
    private func u32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private func u64(_ value: UInt64) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private func string(_ value: String) -> Data { u32(UInt32(value.utf8.count)) + Data(value.utf8) }

    private func record(
        kind: UInt8,
        flags: UInt8,
        _ module: String,
        _ suite: String,
        _ name: String,
        _ images: [(UInt32, [UInt32])]
    ) -> Data {
        var data = Data([kind, flags, 0, 0]) + string(module) + string(suite) + string(name) + u32(UInt32(images.count))
        for (index, counters) in images {
            data += u32(index) + u32(UInt32(counters.count))
            for counter in counters {
                data += u32(counter)
            }
        }
        return data
    }

    @Test func readsTheObserversRecordsAndStopsAtATruncatedOne() {
        let whole = record(kind: 1, flags: 0, "AppTests", "MathTests", "testAdd", [(0, [3, 4]), (2, [9])])
            + record(kind: 2, flags: 1, "AppTests", "SwiftTests", "adds()", [])
        let truncated = record(kind: 0, flags: 0, "AppTests", "", "", [(0, [1])]).dropLast(2)

        #expect(CoverageObserverOutput.parseRecords(whole + truncated) == [
            .init(
                kind: .xctest,
                overlapped: false,
                module: "AppTests",
                suite: "MathTests",
                name: "testAdd",
                counters: [0: [3, 4], 2: [9]]
            ),
            .init(kind: .swiftTesting, overlapped: true, module: "AppTests", suite: "SwiftTests", name: "adds()", counters: [:]),
        ])
    }

    @Test func readsTheNamesOfAnUncompressedSection() {
        let names = Data("$s3App3addyS2i_SitF".utf8) + Data([0x01]) + Data("main.c:helper".utf8)
        let section = Data([UInt8(names.count), 0]) + names

        #expect(CoverageObserverOutput.parseNames(section) == ["$s3App3addyS2i_SitF", "main.c:helper"])
    }

    @Test func refersToANameByTheLow64BitsOfItsMD5() {
        // md5("main") = fad58de7366495db4650cfefac2fcd61
        #expect(CoverageObserverOutput.nameReference("main") == 0xDB95_6436_E78D_D5FA)
    }

    @Test func mapsCountersToFunctionsThroughRelativeRecords() {
        let dataAddress: UInt64 = 0x1000
        let countersAddress: UInt64 = 0x2000
        func profileRecord(index: Int, name: String, firstCounter: Int, count: UInt32) -> Data {
            let recordAddress = Int64(dataAddress) + Int64(index * 64)
            let pointer = Int64(countersAddress) + Int64(firstCounter * 8) - recordAddress
            var data = u64(CoverageObserverOutput.nameReference(name)) + u64(0) + u64(UInt64(bitPattern: pointer))
            data += Data(count: 24) + u32(count)
            return data + Data(count: 64 - data.count)
        }
        let data = profileRecord(index: 0, name: "add", firstCounter: 0, count: 2)
            + profileRecord(index: 1, name: "sign", firstCounter: 2, count: 3)

        #expect(
            CoverageObserverOutput.functionByCounter(
                data: data, names: ["add", "sign"], dataAddress: dataAddress, countersAddress: countersAddress, countersSize: 40
            ) == ["add", "add", "sign", "sign", "sign"]
        )
        #expect(
            CoverageObserverOutput.functionByCounter(
                data: Data(count: 10), names: [], dataAddress: dataAddress, countersAddress: countersAddress, countersSize: 16
            ) == [nil, nil]
        )
    }
}
