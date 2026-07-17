import Command
import Foundation
import Path

/// Reads index unit files by shelling out to `absolute-unit`, the reader that ships alongside the
/// vendored `index-import` binary.
///
/// This runs one process per unit, which is acceptable for the module sizes we cache but is the main
/// candidate for a future in-process reader linked against `libIndexStore`.
public struct AbsoluteUnitIndexStoreUnitReader: IndexStoreUnitReading {
    private let absoluteUnitPath: AbsolutePath
    private let commandRunner: CommandRunning

    public init(
        absoluteUnitPath: AbsolutePath,
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.absoluteUnitPath = absoluteUnitPath
        self.commandRunner = commandRunner
    }

    public func readUnit(at path: AbsolutePath) async throws -> IndexStoreUnit {
        let output = try await commandRunner.run(
            arguments: [absoluteUnitPath.pathString, path.pathString]
        )
        .concatenatedString()
        return AbsoluteUnitOutputParser.parse(output)
    }
}
