import FileSystem
import Foundation
import Mockable
import Path

/// The parts of an index-store unit file the slicer needs to attribute and copy it.
public struct IndexStoreUnit: Equatable, Sendable {
    /// The compiler output path recorded in the unit. Xcode writes this as
    /// `<derivedData>/…/<TargetName>.build/…/<file>.o`, which is how a unit is attributed to a target.
    public let outputFile: String
    /// Names of the record files this unit depends on, e.g. `Greeter.swift-3HUMJXAQF23WH`.
    public let recordNames: [String]

    public init(outputFile: String, recordNames: [String]) {
        self.outputFile = outputFile
        self.recordNames = recordNames
    }
}

@Mockable
public protocol IndexStoreUnitReading {
    /// Reads a single unit file, returning its output path and referenced record names.
    func readUnit(at path: AbsolutePath) async throws -> IndexStoreUnit
}

/// Splits the single index store produced by a cache-warm build into a per-target slice.
///
/// A warm build writes every target's index units into one shared `Index.noindex/DataStore`
/// (`INDEX_DATA_STORE_DIR` is ignored by xcodebuild). To ship a target's index inside its own cache
/// artifact, we copy only the units whose output path names that target's build directory, together
/// with the record files they reference. Units are attributed by output path rather than by module
/// name because clang `…_vers.o` units carry an empty module name.
public struct IndexStoreSlicer {
    private let unitReader: IndexStoreUnitReading
    private let fileSystem: FileSysteming

    public init(
        unitReader: IndexStoreUnitReading,
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.unitReader = unitReader
        self.fileSystem = fileSystem
    }

    /// Copies the slice of `store` that belongs to `targetName` into `destination`, preserving the
    /// `v5/units` and `v5/records` layout so the result is itself a valid index store.
    public func slice(
        store: AbsolutePath,
        targetName: String,
        into destination: AbsolutePath
    ) async throws {
        let unitsDirectory = store.appending(components: "v5", "units")
        guard try await fileSystem.exists(unitsDirectory) else { return }

        let buildDirectoryComponent = "/\(targetName).build/"
        let destinationUnits = destination.appending(components: "v5", "units")
        let destinationRecords = destination.appending(components: "v5", "records")

        var copiedRecordNames = Set<String>()
        var createdUnitsDirectory = false

        for unitPath in try await fileSystem.glob(directory: unitsDirectory, include: ["*"]).collect().sorted() {
            guard let unit = try? await unitReader.readUnit(at: unitPath),
                  unit.outputFile.contains(buildDirectoryComponent)
            else { continue }

            if !createdUnitsDirectory {
                try await fileSystem.makeDirectory(at: destinationUnits)
                createdUnitsDirectory = true
            }
            try await fileSystem.copy(unitPath, to: destinationUnits.appending(component: unitPath.basename))

            for recordName in unit.recordNames where !copiedRecordNames.contains(recordName) {
                guard let shard = Self.recordShard(for: recordName) else { continue }
                let source = store.appending(components: "v5", "records", shard, recordName)
                guard try await fileSystem.exists(source) else { continue }
                let destinationShard = destinationRecords.appending(component: shard)
                if !(try await fileSystem.exists(destinationShard)) {
                    try await fileSystem.makeDirectory(at: destinationShard)
                }
                try await fileSystem.copy(source, to: destinationShard.appending(component: recordName))
                copiedRecordNames.insert(recordName)
            }
        }
    }

    /// Record files are sharded into a subdirectory named after the last two characters of the record
    /// name, e.g. `Greeter.swift-3HUMJXAQF23WH` lives under `records/WH`.
    static func recordShard(for recordName: String) -> String? {
        guard recordName.count >= 2 else { return nil }
        return String(recordName.suffix(2))
    }
}
