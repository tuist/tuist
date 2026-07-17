import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing

@testable import TuistCore

@Suite
struct IndexStoreSlicerTests {
    @Test func recordShard_takes_last_two_characters() {
        #expect(IndexStoreSlicer.recordShard(for: "Greeter.swift-3HUMJXAQF23WH") == "WH")
        #expect(IndexStoreSlicer.recordShard(for: "a") == nil)
    }

    @Test(.inTemporaryDirectory) func slices_units_and_records_for_the_target_only() async throws {
        // Given
        let fileSystem = FileSystem()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let store = temporaryDirectory.appending(component: "store")
        let destination = temporaryDirectory.appending(component: "slice")

        // A shared store with two ModuleA units (one of them the clang `_vers.o` unit that carries an
        // empty module name) and one ModuleB unit that must be excluded.
        let units: [String: IndexStoreUnit] = [
            "A.o-1": IndexStoreUnit(
                outputFile: "/dd/Build/Intermediates.noindex/App.build/ModuleA.build/Objects-normal/arm64/A.o",
                recordNames: ["A.swift-AAAAAAAAAAAW1"]
            ),
            "ModuleA_vers.o-2": IndexStoreUnit(
                outputFile: "/dd/Build/Intermediates.noindex/App.build/ModuleA.build/Objects-normal/arm64/ModuleA_vers.o",
                recordNames: ["ModuleA_vers.swift-BBBBBBBBBBBW2"]
            ),
            "B.o-3": IndexStoreUnit(
                outputFile: "/dd/Build/Intermediates.noindex/App.build/ModuleB.build/Objects-normal/arm64/B.o",
                recordNames: ["B.swift-CCCCCCCCCCCW3"]
            ),
        ]
        try await writeStore(units: units, at: store, fileSystem: fileSystem)

        let reader = MockIndexStoreUnitReading()
        given(reader).readUnit(at: .any).willProduce { path in
            try #require(units[path.basename])
        }

        // When
        let subject = IndexStoreSlicer(unitReader: reader, fileSystem: fileSystem)
        try await subject.slice(store: store, targetName: "ModuleA", into: destination)

        // Then
        let slicedUnits = try await fileSystem
            .glob(directory: destination.appending(components: "v5", "units"), include: ["*"])
            .collect()
            .map(\.basename)
            .sorted()
        #expect(slicedUnits == ["A.o-1", "ModuleA_vers.o-2"])

        #expect(try await fileSystem.exists(destination.appending(components: "v5", "records", "W1", "A.swift-AAAAAAAAAAAW1")))
        #expect(try await fileSystem.exists(
            destination.appending(components: "v5", "records", "W2", "ModuleA_vers.swift-BBBBBBBBBBBW2")
        ))
        // ModuleB's record must not be copied.
        #expect(!(try await fileSystem.exists(destination.appending(components: "v5", "records", "W3", "B.swift-CCCCCCCCCCCW3"))))
    }

    @Test(.inTemporaryDirectory) func no_op_when_store_has_no_units_directory() async throws {
        let fileSystem = FileSystem()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let store = temporaryDirectory.appending(component: "empty-store")
        let destination = temporaryDirectory.appending(component: "slice")

        let reader = MockIndexStoreUnitReading()
        let subject = IndexStoreSlicer(unitReader: reader, fileSystem: fileSystem)

        try await subject.slice(store: store, targetName: "ModuleA", into: destination)
        #expect(!(try await fileSystem.exists(destination)))
    }

    private func writeStore(
        units: [String: IndexStoreUnit],
        at store: AbsolutePath,
        fileSystem: FileSysteming
    ) async throws {
        let unitsDirectory = store.appending(components: "v5", "units")
        try await fileSystem.makeDirectory(at: unitsDirectory)
        for (name, unit) in units {
            try await fileSystem.writeText("unit", at: unitsDirectory.appending(component: name))
            for recordName in unit.recordNames {
                let shard = try #require(IndexStoreSlicer.recordShard(for: recordName))
                let shardDirectory = store.appending(components: "v5", "records", shard)
                if !(try await fileSystem.exists(shardDirectory)) {
                    try await fileSystem.makeDirectory(at: shardDirectory)
                }
                try await fileSystem.writeText("record", at: shardDirectory.appending(component: recordName))
            }
        }
    }
}
