import FileSystem
import Foundation
import Path

public class MockFileSystem: FileSysteming {
    public var existsOverride: ((AbsolutePath) async throws -> Bool) = { _ in true }
    public var existsInDirectoryOverride: ((AbsolutePath, Bool) async throws -> Bool) = { _, _ in true }
    public var touchOverride: ((AbsolutePath) async throws -> Void) = { _ in }
    public var removeOverride: ((AbsolutePath) async throws -> Void) = { _ in }
    public var makeTemporaryDirectoryOverride: ((String) async throws -> AbsolutePath) = { prefix in
        return try AbsolutePath(validating: "/tmp/\(prefix)\(UUID().uuidString)")
    }

    public var contentsOfDirectoryOverride: ((_ path: Path.AbsolutePath) async throws -> [Path.AbsolutePath]) = { _ in [] }
    public func contentsOfDirectory(_ path: Path.AbsolutePath) async throws -> [Path.AbsolutePath] {
        try await contentsOfDirectoryOverride(path)
    }

    public var readFileOverride: ((AbsolutePath) async throws -> Data) = { _ in throw NSError(
        domain: "File not found",
        code: 404,
        userInfo: nil
    ) }
    public var readTextFileOverride: ((Path.AbsolutePath, String.Encoding) async throws -> String) = { _, _ in throw NSError(
        domain: "File not found",
        code: 404,
        userInfo: nil
    ) }
    public var writeTextOverride: ((String, AbsolutePath, String.Encoding) async throws -> Void) = { _, _, _ in }
    public var fileSizeInBytesOverride: ((AbsolutePath) async throws -> Int64?) = { _ in return nil }
    public var currentWorkingDirectoryOverride: (() async throws -> AbsolutePath) = {
        return try AbsolutePath(validating: FileManager.default.currentDirectoryPath)
    }

    public var moveOverride: ((AbsolutePath, AbsolutePath, [MoveOptions]) async throws -> Void) = { _, _, _ in }
    public var makeDirectoryOverride: ((AbsolutePath, [MakeDirectoryOptions]) async throws -> Void) = { _, _ in }
    public var readPlistFileOverride: ((AbsolutePath, PropertyListDecoder) async throws -> Any) = { _, _ in throw NSError(
        domain: "File not found",
        code: 404,
        userInfo: nil
    ) }
    public var writeAsPlistOverride: ((Encodable, AbsolutePath, PropertyListEncoder) async throws -> Void) = { _, _, _ in }
    public var readJSONFileOverride: ((AbsolutePath, JSONDecoder) async throws -> Any) = { _, _ in throw NSError(
        domain: "File not found",
        code: 404,
        userInfo: nil
    ) }
    public var writeAsJSONOverride: ((Encodable, AbsolutePath, JSONEncoder) async throws -> Void) = { _, _, _ in }
    public var replaceOverride: ((AbsolutePath, AbsolutePath) async throws -> Void) = { _, _ in }
    public var copyOverride: ((AbsolutePath, AbsolutePath) async throws -> Void) = { _, _ in }
    public var locateTraversingUpOverride: ((AbsolutePath, RelativePath) async throws -> AbsolutePath?) = { _, _ in return nil }
    public var createSymbolicLinkOverride: ((AbsolutePath, AbsolutePath) async throws -> Void) = { _, _ in }
    public var createRelativeSymbolicLinkOverride: ((AbsolutePath, RelativePath) async throws -> Void) = { _, _ in }
    public var resolveSymbolicLinkOverride: ((AbsolutePath) async throws -> AbsolutePath) = { symlinkPath in return symlinkPath }
    public var zipFileOrDirectoryContentOverride: ((AbsolutePath, AbsolutePath) async throws -> Void) = { _, _ in }
    public var unzipOverride: ((AbsolutePath, AbsolutePath) async throws -> Void) = { _, _ in }
    public var globOverride: ((AbsolutePath, [String]) throws -> AnyThrowingAsyncSequenceable<Path.AbsolutePath>) = { _, _ in
        throw NSError(
            domain: "File not found",
            code: 404,
            userInfo: nil
        )
    }

    public init() {}

    public func runInTemporaryDirectory<T>(
        prefix _: String,
        _: @Sendable (Path.AbsolutePath) async throws -> T
    ) async throws -> T {
        throw NSError(domain: "File not found", code: 404, userInfo: nil)
    }

    public func exists(_ path: Path.AbsolutePath) async throws -> Bool {
        try await exists(path, isDirectory: false)
    }

    public func exists(_ path: Path.AbsolutePath, isDirectory: Bool) async throws -> Bool {
        try await existsInDirectoryOverride(path, isDirectory)
    }

    public func touch(_ path: Path.AbsolutePath) async throws {
        try await touchOverride(path)
    }

    public func remove(_ path: Path.AbsolutePath) async throws {
        try await removeOverride(path)
    }

    public func makeTemporaryDirectory(prefix: String) async throws -> Path.AbsolutePath {
        try await makeTemporaryDirectoryOverride(prefix)
    }

    public func move(from: Path.AbsolutePath, to: Path.AbsolutePath) async throws {
        try await move(from: from, to: to, options: [])
    }

    public func move(from: Path.AbsolutePath, to: Path.AbsolutePath, options: [MoveOptions]) async throws {
        try await moveOverride(from, to, options)
    }

    public func makeDirectory(at: Path.AbsolutePath) async throws {
        try await makeDirectory(at: at, options: [])
    }

    public func makeDirectory(at: Path.AbsolutePath, options: [MakeDirectoryOptions]) async throws {
        try await makeDirectoryOverride(at, options)
    }

    public func readFile(at: Path.AbsolutePath) async throws -> Data {
        try await readFileOverride(at)
    }

    public func readTextFile(at: Path.AbsolutePath) async throws -> String {
        try await readTextFile(at: at, encoding: .utf8)
    }

    public func readTextFile(at: Path.AbsolutePath, encoding: String.Encoding) async throws -> String {
        try await readTextFileOverride(at, encoding)
    }

    public func writeText(_ text: String, at: Path.AbsolutePath) async throws {
        try await writeText(text, at: at, encoding: .utf8)
    }

    public func writeText(_ text: String, at: Path.AbsolutePath, encoding: String.Encoding) async throws {
        try await writeTextOverride(text, at, encoding)
    }

    public func writeText(
        _ text: String,
        at: Path.AbsolutePath,
        encoding: String.Encoding,
        options _: Set<WriteTextOptions>
    ) async throws {
        try await writeTextOverride(text, at, encoding)
    }

    public func readPlistFile<T>(at: Path.AbsolutePath) async throws -> T where T: Decodable {
        try await readPlistFile(at: at, decoder: .init())
    }

    public func readPlistFile<T>(at: Path.AbsolutePath, decoder: PropertyListDecoder) async throws -> T where T: Decodable {
        try await readPlistFileOverride(at, decoder) as! T
    }

    public func writeAsPlist(_ item: some Encodable, at: Path.AbsolutePath) async throws {
        try await writeAsPlist(item, at: at, encoder: .init())
    }

    public func writeAsPlist(_ item: some Encodable, at: Path.AbsolutePath, encoder: PropertyListEncoder) async throws {
        try await writeAsPlistOverride(item, at, encoder)
    }

    public func writeAsPlist(
        _ item: some Encodable,
        at: Path.AbsolutePath,
        encoder: PropertyListEncoder,
        options _: Set<WritePlistOptions>
    ) async throws {
        try await writeAsPlistOverride(item, at, encoder)
    }

    public func readJSONFile<T>(at: Path.AbsolutePath) async throws -> T where T: Decodable {
        try await readJSONFile(at: at, decoder: .init())
    }

    public func readJSONFile<T>(at: Path.AbsolutePath, decoder: JSONDecoder) async throws -> T where T: Decodable {
        try await readJSONFileOverride(at, decoder) as! T
    }

    public func writeAsJSON(_ item: some Encodable, at: Path.AbsolutePath) async throws {
        try await writeAsJSON(item, at: at, encoder: .init())
    }

    public func writeAsJSON(_ item: some Encodable, at: Path.AbsolutePath, encoder: JSONEncoder) async throws {
        try await writeAsJSONOverride(item, at, encoder)
    }

    public func writeAsJSON(
        _ item: some Encodable,
        at: Path.AbsolutePath,
        encoder: JSONEncoder,
        options _: Set<WriteJSONOptions>
    ) async throws {
        try await writeAsJSONOverride(item, at, encoder)
    }

    public func fileSizeInBytes(at: Path.AbsolutePath) async throws -> Int64? {
        try await fileSizeInBytesOverride(at)
    }

    public func replace(_ to: Path.AbsolutePath, with: Path.AbsolutePath) async throws {
        try await replaceOverride(to, with)
    }

    public func copy(_ from: Path.AbsolutePath, to: Path.AbsolutePath) async throws {
        try await copyOverride(from, to)
    }

    public func locateTraversingUp(from: Path.AbsolutePath, relativePath: Path.RelativePath) async throws -> Path.AbsolutePath? {
        try await locateTraversingUpOverride(from, relativePath)
    }

    public func createSymbolicLink(from: Path.AbsolutePath, to: Path.RelativePath) async throws {
        try await createRelativeSymbolicLinkOverride(from, to)
    }

    public func createSymbolicLink(from: Path.AbsolutePath, to: Path.AbsolutePath) async throws {
        try await createSymbolicLinkOverride(from, to)
    }

    public func resolveSymbolicLink(_ symlinkPath: Path.AbsolutePath) async throws -> Path.AbsolutePath {
        try await resolveSymbolicLinkOverride(symlinkPath)
    }

    public func zipFileOrDirectoryContent(at path: Path.AbsolutePath, to: Path.AbsolutePath) async throws {
        try await zipFileOrDirectoryContentOverride(path, to)
    }

    public func unzip(_ zipPath: Path.AbsolutePath, to: Path.AbsolutePath) async throws {
        try await unzipOverride(zipPath, to)
    }

    public func glob(
        directory _: Path.AbsolutePath,
        include _: [String]
    ) throws -> AnyThrowingAsyncSequenceable<Path.AbsolutePath> {
        throw NSError()
    }

    public func currentWorkingDirectory() async throws -> Path.AbsolutePath {
        try await currentWorkingDirectoryOverride()
    }

    public var fileMetadataOverride: ((AbsolutePath) async throws -> FileMetadata?) = { _ in nil }

    public func fileMetadata(at path: Path.AbsolutePath) async throws -> FileMetadata? {
        return try await fileMetadataOverride(path)
    }
}
