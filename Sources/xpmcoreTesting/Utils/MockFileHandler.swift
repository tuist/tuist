import Basic
import Foundation
import xpmcore

public final class MockFileHandler: FileHandling {
    public var existsStub: ((AbsolutePath) -> Bool)?
    public var currentPathStub: AbsolutePath?
    public var globStub: ((AbsolutePath, String) -> [AbsolutePath])?
    public var createFolderStub: ((AbsolutePath) throws -> Void)?
    public var deleteStub: ((AbsolutePath) throws -> Void)?
    public var copyStub: ((AbsolutePath, AbsolutePath) -> Void)?
    public var isFolderStub: ((AbsolutePath) -> Bool)?

    public var currentPath: AbsolutePath {
        return currentPathStub ?? AbsolutePath.current
    }

    public func exists(_ path: AbsolutePath) -> Bool {
        return existsStub?(path) ?? false
    }

    public func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath] {
        return globStub?(path, glob) ?? []
    }

    public func createFolder(_ path: AbsolutePath) throws {
        try createFolderStub?(path)
    }

    public func copy(from: AbsolutePath, to: AbsolutePath) throws {
        copyStub?(from, to)
    }

    public func delete(_ path: AbsolutePath) throws {
        try deleteStub?(path)
    }

    public func isFolder(_ path: AbsolutePath) -> Bool {
        return isFolderStub?(path) ?? false
    }
}
