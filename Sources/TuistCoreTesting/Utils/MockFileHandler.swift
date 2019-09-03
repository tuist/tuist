import Basic
import Foundation
import TuistCore
import XCTest

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

    public func replace(_ to: AbsolutePath, with: AbsolutePath) throws {
        try fileHandler.replace(to, with: with)
    }

    public func inTemporaryDirectory(_ closure: (AbsolutePath) throws -> Void) throws {
        try closure(currentPath)
    }

    public func exists(_ path: AbsolutePath, followSymlink: Bool) -> Bool {
        return fileHandler.exists(path, followSymlink: followSymlink)
    }

    public func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath] {
        return fileHandler.glob(path, glob: glob)
    }

    public func createFolder(_ path: AbsolutePath) throws {
        try fileHandler.createFolder(path)
    }
    
    public func createSymbolicLink(_ path: AbsolutePath, destination: AbsolutePath) throws {
        try fileHandler.createSymbolicLink(path, destination: destination)
    }

    public func copy(from: AbsolutePath, to: AbsolutePath) throws {
        try fileHandler.copy(from: from, to: to)
    }

    public func delete(_ path: AbsolutePath) throws {
        try fileHandler.delete(path)
    }

    public func touch(_ path: AbsolutePath) throws {
        try fileHandler.touch(path)
    }

    public func readTextFile(_ at: AbsolutePath) throws -> String {
        return try fileHandler.readTextFile(at)
    }

    public func isFolder(_ path: AbsolutePath) -> Bool {
        return fileHandler.isFolder(path)
    }

    public func write(_ content: String, path: AbsolutePath, atomically: Bool) throws {
        return try fileHandler.write(content, path: path, atomically: atomically)
    }
}

extension MockFileHandler {
    @discardableResult
    func createFiles(_ files: [String]) throws -> [AbsolutePath] {
        let paths = files.map { currentPath.appending(RelativePath($0)) }
        try paths.forEach {
            try touch($0)
        }
        return paths
    }

    @discardableResult
    func createFolders(_ folders: [String]) throws -> [AbsolutePath] {
        let paths = folders.map { currentPath.appending(RelativePath($0)) }
        try paths.forEach {
            try createFolder($0)
        }
        return paths
    }
}

extension XCTestCase {
    func sharedMockFileHandler(file: StaticString = #file, line: UInt = #line) -> MockFileHandler? {
        guard let mock = FileHandler.shared as? MockFileHandler else {
            let message = "FileHandler.shared hasn't been mocked." +
                "You can call mockFileHandler(), or mockEnvironment() to mock the file handler or the environment respectively."
            XCTFail(message, file: file, line: line)
            return nil
        }
        return mock
    }
}
