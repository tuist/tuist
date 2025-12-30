import Path
import TSCBasic

public func withTemporaryDirectories<Result>(body: (Path.AbsolutePath, Path.AbsolutePath) throws -> Result) throws -> Result {
    try withTemporaryDirectory { tempDirOne in
        try withTemporaryDirectory { tempDirTwo in
            try body(.init(validating: tempDirOne.pathString), .init(validating: tempDirTwo.pathString))
        }
    }
}
