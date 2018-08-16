import Basic
import Foundation
import TuistCore

public final class MockFileHandler: FileHandling {
    private let fileHandler: FileHandling
    private let currentDirectory: TemporaryDirectory

    public var currentPath: AbsolutePath {
        return currentDirectory.path
    }

    init() throws {
        currentDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        fileHandler = FileHandler()
    }

    public func exists(_ path: AbsolutePath) -> Bool {
        return fileHandler.exists(path)
    }

    public func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath] {
        return fileHandler.glob(path, glob: glob)
    }

    public func createFolder(_ path: AbsolutePath) throws {
        try fileHandler.createFolder(path)
    }

    public func copy(from: AbsolutePath, to: AbsolutePath) throws {
        try fileHandler.copy(from: from, to: to)
    }

    public func delete(_ path: AbsolutePath) throws {
        try fileHandler.delete(path)
    }

    public func isFolder(_ path: AbsolutePath) -> Bool {
        return fileHandler.isFolder(path)
    }

    public func touch(_ path: AbsolutePath) throws {
        try fileHandler.touch(path)
    }
}
