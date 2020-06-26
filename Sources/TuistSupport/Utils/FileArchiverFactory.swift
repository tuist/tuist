import TSCBasic

public protocol FileArchiverManufacturing {
    func makeFileArchiver(for path: AbsolutePath) -> FileArchiving
}

public class FileArchiverFactory: FileArchiverManufacturing {
    public init() {}

    public func makeFileArchiver(for path: AbsolutePath) -> FileArchiving {
        FileArchiver(path: path)
    }
}
