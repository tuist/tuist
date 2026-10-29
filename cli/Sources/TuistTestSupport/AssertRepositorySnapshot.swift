import SnapshotTesting
import Testing

public func assertRepositorySnapshot<Value>(
    of value: @autoclosure () throws -> Value,
    as snapshotting: Snapshotting<Value, some Any>,
    fileID: StaticString = #fileID,
    file: StaticString = #filePath,
    testName: String = #function,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    do {
        let directory = try TestPaths.snapshotDirectory(filePath: "\(file)")
        if let message = verifySnapshot(
            of: try value(),
            as: snapshotting,
            snapshotDirectory: directory.pathString,
            fileID: fileID,
            file: file,
            testName: testName,
            line: UInt(sourceLocation.line),
            column: UInt(sourceLocation.column)
        ) {
            Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
        }
    } catch {
        Issue.record(error, sourceLocation: sourceLocation)
    }
}
