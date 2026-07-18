import Command
import Foundation
import Path

/// Reads index unit files by shelling out to `absolute-unit`, the reader that ships alongside the
/// vendored `index-import` binary.
///
/// Units are read in batches (one process per batch) to keep the number of spawned processes small
/// and independent of the number of targets. Batches are bounded so the argument list stays well
/// under the OS limit.
public struct AbsoluteUnitIndexStoreUnitReader: IndexStoreUnitReading {
    private let absoluteUnitPath: AbsolutePath
    private let commandRunner: CommandRunning
    private let batchSize: Int

    public init(
        absoluteUnitPath: AbsolutePath,
        commandRunner: CommandRunning = CommandRunner(),
        batchSize: Int = 256
    ) {
        self.absoluteUnitPath = absoluteUnitPath
        self.commandRunner = commandRunner
        self.batchSize = batchSize
    }

    public func readUnits(at paths: [AbsolutePath]) async throws -> [AbsolutePath: IndexStoreUnit] {
        let pathsByString = Dictionary(paths.map { ($0.pathString, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [AbsolutePath: IndexStoreUnit] = [:]

        for batch in paths.chunked(into: batchSize) {
            let output = try await commandRunner.run(
                arguments: [absoluteUnitPath.pathString] + batch.map(\.pathString)
            )
            .concatenatedString()

            for (pathString, unit) in AbsoluteUnitOutputParser.parseAll(output) {
                if let path = pathsByString[pathString] {
                    result[path] = unit
                }
            }
        }

        return result
    }
}

extension Array {
    fileprivate func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
