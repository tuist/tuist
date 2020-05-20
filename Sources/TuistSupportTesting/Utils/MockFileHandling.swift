import Foundation
import TSCBasic
@testable import TuistSupport

/// Mock FileHandling without subclassing

public final class MockFileHandling: FileHandling {
    public var currentPath: AbsolutePath = AbsolutePath("/")

    public func replace(_: AbsolutePath, with _: AbsolutePath) throws {}

    public var existsForPathStub: [AbsolutePath: Bool] = [:]
    public func exists(_ path: AbsolutePath) -> Bool {
        existsForPathStub[path] ?? false
    }

    public func move(from _: AbsolutePath, to _: AbsolutePath) throws {}

    public func copy(from _: AbsolutePath, to _: AbsolutePath) throws {}

    public var readFileStub: Data?
    public var readFileSpy: AbsolutePath?
    public func readFile(_ at: AbsolutePath) throws -> Data {
        readFileSpy = at
        guard let readFileStub = readFileStub else {
            throw NSError(domain: "Mock is missing stub", code: 0, userInfo: nil)
        }
        return readFileStub
    }

    public func readTextFile(_: AbsolutePath) throws -> String {
        ""
    }

    public func readPlistFile<T>(_: AbsolutePath) throws -> T where T: Decodable {
        return try JSONDecoder().decode(T.self, from: Data(capacity: 42))
    }

    public func inTemporaryDirectory(_: (AbsolutePath) throws -> Void) throws {}

    public func write(_: String, path _: AbsolutePath, atomically _: Bool) throws {}

    public func locateDirectoryTraversingParents(from _: AbsolutePath, path _: String) -> AbsolutePath? {
        nil
    }

    public func locateDirectory(_: String, traversingFrom _: AbsolutePath) -> AbsolutePath? {
        nil
    }

    public func glob(_: AbsolutePath, glob _: String) -> [AbsolutePath] {
        []
    }

    public func linkFile(atPath _: AbsolutePath, toPath _: AbsolutePath) throws {}

    public func createFolder(_: AbsolutePath) throws {}

    public func delete(_: AbsolutePath) throws {}

    public func isFolder(_: AbsolutePath) -> Bool {
        false
    }

    public func touch(_: AbsolutePath) throws {}

    public func contentsOfDirectory(_: AbsolutePath) throws -> [AbsolutePath] {
        []
    }
}
