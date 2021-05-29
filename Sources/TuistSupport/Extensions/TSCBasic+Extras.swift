import TSCBasic

public func withTemporaryDirectories<Result>(body: (AbsolutePath, AbsolutePath) throws -> Result) throws -> Result {
    try withTemporaryDirectory { tempDirOne in
        try withTemporaryDirectory { tempDirTwo in
            try body(tempDirOne, tempDirTwo)
        }
    }
}
