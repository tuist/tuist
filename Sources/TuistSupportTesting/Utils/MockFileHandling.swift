import Foundation
@testable import TuistSupport
import TSCBasic

/// Mock FileHandling without subclassing
public final class MockFileHandling: FileHandling {
    public var currentPath: AbsolutePath = AbsolutePath("/")

    public func replace(_ to: AbsolutePath, with: AbsolutePath) throws {
    }

    public var existsForPathStub: [AbsolutePath: Bool] = [:]
    public func exists(_ path: AbsolutePath) -> Bool {
        return existsForPathStub[path] ?? false
    }

    public func move(from: AbsolutePath, to: AbsolutePath) throws {
    }

    public func copy(from: AbsolutePath, to: AbsolutePath) throws {
    }

    public var readFileStub: Data?
    public var readFileSpy: AbsolutePath?
    public func readFile(_ at: AbsolutePath) throws -> Data {
        readFileSpy = at
        guard let readFileStub = readFileStub else {
            throw NSError(domain: "Mock is missing stub", code: 0, userInfo: nil)
        }
        return readFileStub
    }

    public func readTextFile(_ at: AbsolutePath) throws -> String {
        return ""
    }

    public func readPlistFile<T>(_ at: AbsolutePath) throws -> T where T: Decodable {
        return try JSONDecoder().decode(T.self, from: Data(capacity: 42))
    }

    public func inTemporaryDirectory(_ closure: (AbsolutePath) throws -> Void) throws {
    }

    public func write(_ content: String, path: AbsolutePath, atomically: Bool) throws {
    }

    public func locateDirectoryTraversingParents(from: AbsolutePath, path: String) -> AbsolutePath? {
        return nil
    }

    public func locateDirectory(_ path: String, traversingFrom from: AbsolutePath) -> AbsolutePath? {
        return nil
    }

    public func glob(_ path: AbsolutePath, glob: String) -> [AbsolutePath] {
        return []
    }

    public func linkFile(atPath: AbsolutePath, toPath: AbsolutePath) throws {
    }

    public func createFolder(_ path: AbsolutePath) throws {
    }

    public func delete(_ path: AbsolutePath) throws {
    }

    public func isFolder(_ path: AbsolutePath) -> Bool {
        return false
    }

    public func touch(_ path: AbsolutePath) throws {
    }

    public func contentsOfDirectory(_ path: AbsolutePath) throws -> [AbsolutePath] {
        return []
    }
}

