import Basic
import Foundation
@testable import xpmkit

final class MockFileHandler: FileHandling {
    var existsStub: ((AbsolutePath) -> Bool)?
    var currentPathStub: AbsolutePath?
    var globStub: ((AbsolutePath, String) -> [AbsolutePath])?
    var createFolderStub: ((AbsolutePath) throws -> Void)?
    var deleteStub: ((AbsolutePath) throws -> Void)?
    var copyStub: ((AbsolutePath, AbsolutePath) -> Void)?
    var isFolderStub: ((AbsolutePath) -> Bool)?

    var currentPath: AbsolutePath {
        return currentPathStub ?? AbsolutePath.current
    }

    func exists(_ path: AbsolutePath) -> Bool {
        return existsStub?(path) ?? false
    }

    func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath] {
        return globStub?(path, glob) ?? []
    }

    func createFolder(_ path: AbsolutePath) throws {
        try createFolderStub?(path)
    }

    func copy(from: AbsolutePath, to: AbsolutePath) throws {
        copyStub?(from, to)
    }

    func delete(_ path: AbsolutePath) throws {
        try deleteStub?(path)
    }

    func isFolder(_ path: AbsolutePath) -> Bool {
        return isFolderStub?(path) ?? false
    }
}
