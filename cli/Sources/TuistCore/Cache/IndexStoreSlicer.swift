import FileSystem
import Foundation
import Mockable
import Path

/// The parts of an index-store unit file the slicer needs to attribute and copy it.
public struct IndexStoreUnit: Equatable, Sendable {
    /// The compiler output path recorded in the unit. Xcode writes this as
    /// `…/<ProjectName>.build/<Config-Platform>/<TargetName>.build/…/<file>.o`, which is how a unit is
    /// attributed to a target.
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
    /// Reads the given unit files in as few invocations as possible, returning each unit's output path
    /// and referenced record names keyed by its path.
    func readUnits(at paths: [AbsolutePath]) async throws -> [AbsolutePath: IndexStoreUnit]
}

/// Identifies one target's slice: the target and project names used to attribute units, plus the
/// destination the slice is written to.
public struct IndexStoreTargetSlice: Sendable {
    public let targetName: String
    public let projectName: String
    public let destination: AbsolutePath

    public init(targetName: String, projectName: String, destination: AbsolutePath) {
        self.targetName = targetName
        self.projectName = projectName
        self.destination = destination
    }
}

/// Splits the single index store produced by a cache-warm build into per-target slices.
///
/// A warm build writes every target's index units into one shared `Index.noindex/DataStore`
/// (`INDEX_DATA_STORE_DIR` is ignored by xcodebuild). To ship a target's index inside its own cache
/// artifact, we copy the units whose output path names that target's build directory, together with
/// the record files they reference. Units are attributed by output path rather than by module name
/// because clang `…_vers.o` units carry an empty module name, and by both the project and target
/// build-directory segments so that equally named targets in different projects stay separate.
///
/// The shared store is scanned once for all targets, so the number of `absolute-unit` invocations is
/// independent of the number of targets.
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

    /// Slices `store` for every target in `targets` in a single pass, writing each target's units and
    /// referenced records into its destination, preserving the `v5/units` and `v5/records` layout so
    /// the result is itself a valid index store.
    public func slice(store: AbsolutePath, targets: [IndexStoreTargetSlice]) async throws {
        let unitsDirectory = store.appending(components: "v5", "units")
        guard try await fileSystem.exists(unitsDirectory), !targets.isEmpty else { return }

        let unitPaths = try await fileSystem.glob(directory: unitsDirectory, include: ["*"]).collect().sorted()
        guard !unitPaths.isEmpty else { return }

        let units = try await unitReader.readUnits(at: unitPaths)

        // One set of already-copied record names per destination, so records shared across a target's
        // units are copied once.
        var copiedRecordsByDestination: [AbsolutePath: Set<String>] = [:]

        for unitPath in unitPaths {
            guard let unit = units[unitPath],
                  let target = targets.first(where: { attributes(unit, to: $0) })
            else { continue }

            let destinationUnits = target.destination.appending(components: "v5", "units")
            try await fileSystem.makeDirectory(at: destinationUnits)
            try await fileSystem.copy(unitPath, to: destinationUnits.appending(component: unitPath.basename))

            var copiedRecords = copiedRecordsByDestination[target.destination] ?? []
            for recordName in unit.recordNames where !copiedRecords.contains(recordName) {
                guard let shard = Self.recordShard(for: recordName) else { continue }
                let source = store.appending(components: "v5", "records", shard, recordName)
                guard try await fileSystem.exists(source) else { continue }
                let destinationShard = target.destination.appending(components: "v5", "records", shard)
                if !(try await fileSystem.exists(destinationShard)) {
                    try await fileSystem.makeDirectory(at: destinationShard)
                }
                try await fileSystem.copy(source, to: destinationShard.appending(component: recordName))
                copiedRecords.insert(recordName)
            }
            copiedRecordsByDestination[target.destination] = copiedRecords
        }
    }

    /// A unit belongs to a target when its output path contains both the project's and the target's
    /// build-directory segments. Matching both keeps equally named targets in different projects apart.
    private func attributes(_ unit: IndexStoreUnit, to target: IndexStoreTargetSlice) -> Bool {
        unit.outputFile.contains("/\(target.projectName).build/")
            && unit.outputFile.contains("/\(target.targetName).build/")
    }

    /// Record files are sharded into a subdirectory named after the last two characters of the record
    /// name, e.g. `Greeter.swift-3HUMJXAQF23WH` lives under `records/WH`.
    static func recordShard(for recordName: String) -> String? {
        guard recordName.count >= 2 else { return nil }
        return String(recordName.suffix(2))
    }
}
