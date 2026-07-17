import Command
import Foundation
import Mockable
import Path

@Mockable
public protocol IndexStoreImporting {
    /// Imports a cached module's index store slice into the workspace's index data store, remapping
    /// the hermetic tokens back to the developer's local paths.
    func importStore(
        _ store: AbsolutePath,
        into dataStore: AbsolutePath,
        sourceRoot: AbsolutePath,
        derivedData: AbsolutePath
    ) async throws
}

/// Imports index store slices with the vendored `index-import` binary.
public struct IndexStoreImporter: IndexStoreImporting {
    private let indexImportPath: AbsolutePath
    private let commandRunner: CommandRunning

    public init(
        indexImportPath: AbsolutePath,
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.indexImportPath = indexImportPath
        self.commandRunner = commandRunner
    }

    public func importStore(
        _ store: AbsolutePath,
        into dataStore: AbsolutePath,
        sourceRoot: AbsolutePath,
        derivedData: AbsolutePath
    ) async throws {
        _ = try await commandRunner.run(
            arguments: Self.arguments(
                indexImportPath: indexImportPath,
                store: store,
                dataStore: dataStore,
                sourceRoot: sourceRoot,
                derivedData: derivedData
            )
        )
        .concatenatedString()
    }

    /// Builds the `index-import` invocation. The two `-remap` rules reverse the `-file-prefix-map`
    /// tokens the warm build baked into the units, restoring the developer's local paths so Xcode can
    /// resolve them.
    static func arguments(
        indexImportPath: AbsolutePath,
        store: AbsolutePath,
        dataStore: AbsolutePath,
        sourceRoot: AbsolutePath,
        derivedData: AbsolutePath
    ) -> [String] {
        [
            indexImportPath.pathString,
            "-remap", "\(CacheIndexStore.sourceRootToken)=\(sourceRoot.pathString)",
            "-remap", "\(CacheIndexStore.buildRootToken)=\(derivedData.pathString)",
            store.pathString,
            dataStore.pathString,
        ]
    }
}
