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

    @Test(.inTemporaryDirectory) func slices_units_and_records_per_target_in_a_single_scan() async throws {
        // Given
        let fileSystem = FileSystem()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let store = temporaryDirectory.appending(component: "store")
        let aDestination = temporaryDirectory.appending(components: "slices", "ModuleA")
        let bDestination = temporaryDirectory.appending(components: "slices", "ModuleB")

        // A shared store with two ModuleA units (one of them the clang `_vers.o` unit that carries an
        // empty module name) and one ModuleB unit.
        let units: [String: IndexStoreUnit] = [
            "A.o-1": IndexStoreUnit(
                outputFile: "/dd/App.build/Debug/ModuleA.build/Objects-normal/arm64/A.o",
                recordNames: ["A.swift-AAAAAAAAAAAW1"]
            ),
            "ModuleA_vers.o-2": IndexStoreUnit(
                outputFile: "/dd/App.build/Debug/ModuleA.build/Objects-normal/arm64/ModuleA_vers.o",
                recordNames: ["ModuleA_vers.swift-BBBBBBBBBBBW2"]
            ),
            "B.o-3": IndexStoreUnit(
                outputFile: "/dd/App.build/Debug/ModuleB.build/Objects-normal/arm64/B.o",
                recordNames: ["B.swift-CCCCCCCCCCCW3"]
            ),
        ]
        try await writeStore(units: units, at: store, fileSystem: fileSystem)
        let reader = try batchReader(returning: units)

        // When
        let subject = IndexStoreSlicer(unitReader: reader, fileSystem: fileSystem)
        try await subject.slice(store: store, targets: [
            IndexStoreTargetSlice(targetName: "ModuleA", projectName: "App", destination: aDestination),
            IndexStoreTargetSlice(targetName: "ModuleB", projectName: "App", destination: bDestination),
        ])

        // Then: ModuleA's slice has both its units (including the empty-module-name one) and its records.
        #expect(try await unitBasenames(in: aDestination, fileSystem: fileSystem) == ["A.o-1", "ModuleA_vers.o-2"])
        #expect(try await fileSystem.exists(aDestination.appending(components: "v5", "records", "W1", "A.swift-AAAAAAAAAAAW1")))
        #expect(try await fileSystem.exists(
            aDestination.appending(components: "v5", "records", "W2", "ModuleA_vers.swift-BBBBBBBBBBBW2")
        ))
        #expect(!(try await fileSystem.exists(aDestination.appending(
            components: "v5",
            "records",
            "W3",
            "B.swift-CCCCCCCCCCCW3"
        ))))

        // And ModuleB's slice only has its own unit.
        #expect(try await unitBasenames(in: bDestination, fileSystem: fileSystem) == ["B.o-3"])
    }

    @Test(.inTemporaryDirectory) func keeps_equally_named_targets_in_different_projects_separate() async throws {
        // Given: two targets both named "Feature" in different projects.
        let fileSystem = FileSystem()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let store = temporaryDirectory.appending(component: "store")
        let firstDestination = temporaryDirectory.appending(components: "slices", "first")
        let secondDestination = temporaryDirectory.appending(components: "slices", "second")

        let units: [String: IndexStoreUnit] = [
            "first.o-1": IndexStoreUnit(
                outputFile: "/dd/ProjectA.build/Debug/Feature.build/Objects-normal/arm64/first.o",
                recordNames: []
            ),
            "second.o-2": IndexStoreUnit(
                outputFile: "/dd/ProjectB.build/Debug/Feature.build/Objects-normal/arm64/second.o",
                recordNames: []
            ),
        ]
        try await writeStore(units: units, at: store, fileSystem: fileSystem)
        let reader = try batchReader(returning: units)

        // When
        let subject = IndexStoreSlicer(unitReader: reader, fileSystem: fileSystem)
        try await subject.slice(store: store, targets: [
            IndexStoreTargetSlice(targetName: "Feature", projectName: "ProjectA", destination: firstDestination),
            IndexStoreTargetSlice(targetName: "Feature", projectName: "ProjectB", destination: secondDestination),
        ])

        // Then: each slice contains only its own project's unit.
        #expect(try await unitBasenames(in: firstDestination, fileSystem: fileSystem) == ["first.o-1"])
        #expect(try await unitBasenames(in: secondDestination, fileSystem: fileSystem) == ["second.o-2"])
    }

    @Test(.inTemporaryDirectory) func no_op_when_store_has_no_units_directory() async throws {
        let fileSystem = FileSystem()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let store = temporaryDirectory.appending(component: "empty-store")
        let destination = temporaryDirectory.appending(component: "slice")

        let reader = MockIndexStoreUnitReading()
        let subject = IndexStoreSlicer(unitReader: reader, fileSystem: fileSystem)

        try await subject.slice(store: store, targets: [
            IndexStoreTargetSlice(targetName: "ModuleA", projectName: "App", destination: destination),
        ])
        #expect(!(try await fileSystem.exists(destination)))
    }

    // MARK: - Helpers

    private func batchReader(returning units: [String: IndexStoreUnit]) throws -> MockIndexStoreUnitReading {
        let reader = MockIndexStoreUnitReading()
        given(reader).readUnits(at: .any).willProduce { paths in
            Dictionary(uniqueKeysWithValues: paths.compactMap { path in
                units[path.basename].map { (path, $0) }
            })
        }
        return reader
    }

    private func unitBasenames(in destination: AbsolutePath, fileSystem: FileSysteming) async throws -> [String] {
        try await fileSystem
            .glob(directory: destination.appending(components: "v5", "units"), include: ["*"])
            .collect()
            .map(\.basename)
            .sorted()
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
