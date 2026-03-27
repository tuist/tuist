import FileSystem
import Path
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest
@testable import TuistGenerator
@testable import TuistTesting

final class WorkspaceStructureGeneratorTests: XCTestCase {
    fileprivate var fileSystem: InMemoryFileSystem!
    var subject: WorkspaceStructureGenerator!

    override func setUp() {
        fileSystem = InMemoryFileSystem()
        subject = WorkspaceStructureGenerator()
    }

    override func tearDown() {
        fileSystem = nil
        subject = nil
    }

    func test_generateStructure_projects() async throws {
        // Given
        let xcodeProjPaths = try createFolders([
            "/path/to/workspace/Modules/A/Project.xcodeproj",
            "/path/to/workspace/Modules/B/Project.xcodeproj",
            "/path/to/workspace/Modules/Sub/C/Project.xcodeproj",
            "/path/to/workspace/Modules/Sub/D/Project.xcodeproj",
        ])

        // When
        let structure = try await subject.generateStructure(
            path: "/path/to/workspace",
            workspace: Workspace.test(),
            xcodeProjPaths: xcodeProjPaths,
            fileSystem: fileSystem
        )

        // Then
        XCTAssertEqual(structure.contents, [
            .group("Modules", "/path/to/workspace/Modules", [
                .project("/path/to/workspace/Modules/A/Project.xcodeproj"),
                .project("/path/to/workspace/Modules/B/Project.xcodeproj"),
                .group("Sub", "/path/to/workspace/Modules/Sub", [
                    .project("/path/to/workspace/Modules/Sub/C/Project.xcodeproj"),
                    .project("/path/to/workspace/Modules/Sub/D/Project.xcodeproj"),
                ]),
            ]),
        ])
    }

    func test_generateStructure_projectsAndFiles() async throws {
        // Given
        let xcodeProjPaths = try createFolders([
            "/path/to/workspace/Modules/A/Project.xcodeproj",
            "/path/to/workspace/Modules/B/Project.xcodeproj",
        ])

        let files = try createFiles([
            "/path/to/workspace/Documentation/README.md",
            "/path/to/workspace/Documentation/setup/usage.md",
            "/path/to/workspace/Documentation/generate/guide.md",
            "/path/to/workspace/README.md",
        ])

        let workspace = Workspace.test(
            additionalFiles: files.map { .file(path: $0) }
        )

        // When
        let structure = try await subject.generateStructure(
            path: "/path/to/workspace",
            workspace: workspace,
            xcodeProjPaths: xcodeProjPaths,
            fileSystem: fileSystem
        )

        // Then
        XCTAssertEqual(structure.contents, [
            .group("Documentation", "/path/to/workspace/Documentation", [
                .file("/path/to/workspace/Documentation/README.md"),
                .group("generate", "/path/to/workspace/Documentation/generate", [
                    .file("/path/to/workspace/Documentation/generate/guide.md"),
                ]),
                .group("setup", "/path/to/workspace/Documentation/setup", [
                    .file("/path/to/workspace/Documentation/setup/usage.md"),
                ]),
            ]),
            .group("Modules", "/path/to/workspace/Modules", [
                .project("/path/to/workspace/Modules/A/Project.xcodeproj"),
                .project("/path/to/workspace/Modules/B/Project.xcodeproj"),
            ]),
            .file("/path/to/workspace/README.md"),
        ])
    }

    func test_generateStructure_folderReferences() async throws {
        // Given
        try createFolders([
            "/path/to/workspace/Documentation/Guides",
            "/path/to/workspace/Documentation/Proposals",
        ])

        try createFiles([
            "/path/to/workspace/README.md",
        ])

        let additionalFiles: [FileElement] = [
            .folderReference(path: "/path/to/workspace/Documentation/Guides"),
            .folderReference(path: "/path/to/workspace/Documentation/Proposals"),
            .file(path: "/path/to/workspace/README.md"),
        ]
        let workspace = Workspace.test(additionalFiles: additionalFiles)

        // When
        let structure = try await subject.generateStructure(
            path: "/path/to/workspace",
            workspace: workspace,
            xcodeProjPaths: [],
            fileSystem: fileSystem
        )

        // Then
        XCTAssertEqual(structure.contents, [
            .group("Documentation", "/path/to/workspace/Documentation", [
                .folderReference("/path/to/workspace/Documentation/Guides"),
                .folderReference("/path/to/workspace/Documentation/Proposals"),
            ]),
            .file("/path/to/workspace/README.md"),
        ])
    }

    func test_generateStructure_collapseDirectories() async throws {
        // Given
        try createFiles([
            "/path/to/workspace/Documentation/README.md",
            "/path/to/workspace/Documentation/setup/usage.md",
        ])

        // This is the equivalent of "**" glob
        // which includes both directories and files
        let paths = [
            "/path/to/workspace",
            "/path/to/workspace/Documentation",
            "/path/to/workspace/Documentation/README.md",
            "/path/to/workspace/Documentation/setup",
            "/path/to/workspace/Documentation/setup/usage.md",
        ]
        let workspace = Workspace.test(additionalFiles: paths.map { .file(path: try! AbsolutePath(validating: $0)) })

        // When
        let structure = try await subject.generateStructure(
            path: "/path/to/workspace",
            workspace: workspace,
            xcodeProjPaths: [],
            fileSystem: fileSystem
        )

        // Then
        XCTAssertEqual(structure.contents, [
            .group("Documentation", "/path/to/workspace/Documentation", [
                .file("/path/to/workspace/Documentation/README.md"),
                .group("setup", "/path/to/workspace/Documentation/setup", [
                    .file("/path/to/workspace/Documentation/setup/usage.md"),
                ]),
            ]),
        ])
    }

    func test_generateStructure_excludesFolders() async throws {
        // Given
        try createFolders([
            "/path/to/workspace",
            "/path/to/workspace/Documentation",
        ])

        let paths = [
            "/path/to/workspace",
            "/path/to/workspace/Documentation",
        ]
        let workspace = Workspace.test(additionalFiles: paths.map { .file(path: try! AbsolutePath(validating: $0)) })

        // When
        let structure = try await subject.generateStructure(
            path: "/path/to/workspace",
            workspace: workspace,
            xcodeProjPaths: [],
            fileSystem: fileSystem
        )

        // Then
        XCTAssertEqual(structure.contents, [])
    }

    func test_generateStructure_includesContainerTypes() async throws {
        // Given

        try createFolders([
            "/path/to/workspace/Pods.xcodeproj",
            "/path/to/workspace/Testing.playground",
        ])

        let paths = [
            "/path/to/workspace/Pods.xcodeproj",
            "/path/to/workspace/Testing.playground",
        ]
        let workspace = Workspace.test(additionalFiles: paths.map { .file(path: try! AbsolutePath(validating: $0)) })

        // When
        let structure = try await subject.generateStructure(
            path: "/path/to/workspace",
            workspace: workspace,
            xcodeProjPaths: [],
            fileSystem: fileSystem
        )

        // Then
        XCTAssertEqual(structure.contents, [
            .file("/path/to/workspace/Pods.xcodeproj"),
            .file("/path/to/workspace/Testing.playground"),
        ])
    }

    func test_generateStructure_projectsAndFilesOverlap() async throws {
        // Given
        let xcodeProjPaths = try createFolders([
            "/path/to/workspace/Modules/A/Project.xcodeproj",
        ])

        let files: [FileElement] = [
            .folderReference(path: "/path/to/workspace/Modules/A"),
        ]
        let workspace = Workspace.test(
            additionalFiles: files
        )

        // When
        let structure = try await subject.generateStructure(
            path: "/path/to/workspace",
            workspace: workspace,
            xcodeProjPaths: xcodeProjPaths,
            fileSystem: fileSystem
        )

        // Then
        XCTAssertEqual(structure.contents, [
            .group("Modules", "/path/to/workspace/Modules", [
                .project("/path/to/workspace/Modules/A/Project.xcodeproj"),
                .folderReference("/path/to/workspace/Modules/A"),
            ]),
        ])
    }

    func test_generateStructure_projectsAndNestedFiles() async throws {
        // Given
        let xcodeProjPaths = try createFolders([
            "/path/to/workspace/Modules/A/Project.xcodeproj",
        ])

        let files = try createFiles([
            "/path/to/workspace/Modules/A/README.md",
        ])

        let workspace = Workspace.test(additionalFiles: files.map { .file(path: $0) })

        // When
        let structure = try await subject.generateStructure(
            path: "/path/to/workspace",
            workspace: workspace,
            xcodeProjPaths: xcodeProjPaths,
            fileSystem: fileSystem
        )

        // Then
        XCTAssertEqual(structure.contents, [
            .group("Modules", "/path/to/workspace/Modules", [
                .project("/path/to/workspace/Modules/A/Project.xcodeproj"),
                .group("A", "/path/to/workspace/Modules/A", [
                    .file("/path/to/workspace/Modules/A/README.md"),
                ]),
            ]),
        ])
    }

    func test_generateStructure_addsDependenciesToADependenciesGroup() async throws {
        // Given
        let xcodeProjPaths = try createFolders([
            "/path/to/workspace/Tuist/.build/tuist-derived/AEXML/AEXML.xcodeproj",
            "/path/to/workspace/Tuist/.build/tuist-derived/SwiftSyntax/SwiftSyntax.xcodeproj",
        ])

        let workspace = Workspace.test()

        // When
        let structure = try await subject.generateStructure(
            path: "/path/to/workspace",
            workspace: workspace,
            xcodeProjPaths: xcodeProjPaths,
            fileSystem: fileSystem
        )

        // Then
        XCTAssertEqual(structure.contents, [
            .virtualGroup(name: "Dependencies", contents: [
                .project("/path/to/workspace/Tuist/.build/tuist-derived/AEXML/AEXML.xcodeproj"),
                .project(
                    "/path/to/workspace/Tuist/.build/tuist-derived/SwiftSyntax/SwiftSyntax.xcodeproj"
                ),
            ]),
        ])
    }

    // MARK: - Helpers

    @discardableResult
    func createFolders(_ folders: [String]) throws -> [AbsolutePath] {
        let paths = folders.map { try! AbsolutePath(validating: $0) }
        for path in paths {
            fileSystem.createFolder(path)
        }
        return paths
    }

    @discardableResult
    func createFiles(_ files: [String]) throws -> [AbsolutePath] {
        let paths = files.map { try! AbsolutePath(validating: $0) }
        for path in paths {
            fileSystem.createFile(path)
        }
        return paths
    }

    fileprivate class InMemoryFileSystem: FileSysteming {
        private enum Node {
            case file
            case folder
        }

        private var cache: [AbsolutePath: Node] = [:]

        func createFolder(_ path: AbsolutePath) {
            var pathSoFar: AbsolutePath = "/"
            for component in path.components.dropFirst() {
                pathSoFar = pathSoFar.appending(component: component)
                cache[pathSoFar] = .folder
            }
        }

        func createFile(_ path: AbsolutePath) {
            let parent = path.parentDirectory
            createFolder(parent)
            cache[path] = .file
        }

        func exists(_ path: AbsolutePath) async throws -> Bool {
            cache[path] != nil
        }

        func exists(_ path: AbsolutePath, isDirectory: Bool) async throws -> Bool {
            guard let node = cache[path] else { return false }
            if isDirectory {
                return node == .folder
            }
            return node == .file
        }

        func touch(_ path: AbsolutePath) async throws {
            createFile(path)
        }

        func remove(_ path: AbsolutePath) async throws {
            cache.removeValue(forKey: path)
        }

        func makeTemporaryDirectory(prefix _: String) async throws -> AbsolutePath {
            try AbsolutePath(validating: "/tmp/\(UUID().uuidString)")
        }

        func runInTemporaryDirectory<T>(
            prefix _: String,
            _ closure: @Sendable (AbsolutePath) async throws -> T
        ) async throws -> T {
            try await closure(AbsolutePath(validating: "/tmp"))
        }

        func move(from _: AbsolutePath, to _: AbsolutePath) async throws {}
        func move(from _: AbsolutePath, to _: AbsolutePath, options _: [MoveOptions]) async throws {}
        func makeDirectory(at _: AbsolutePath) async throws {}
        func makeDirectory(at _: AbsolutePath, options _: [MakeDirectoryOptions]) async throws {}
        func readFile(at _: AbsolutePath) async throws -> Data { Data() }
        func readTextFile(at _: AbsolutePath) async throws -> String { "" }
        func readTextFile(at _: AbsolutePath, encoding _: String.Encoding) async throws -> String { "" }
        func writeText(_ _: String, at _: AbsolutePath) async throws {}
        func writeText(_ _: String, at _: AbsolutePath, encoding _: String.Encoding) async throws {}
        func writeText(
            _ _: String,
            at _: AbsolutePath,
            encoding _: String.Encoding,
            options _: Set<WriteTextOptions>
        ) async throws {}
        func readPlistFile<T: Decodable>(at _: AbsolutePath) async throws -> T {
            throw NSError(domain: "Not implemented", code: 0)
        }

        func readPlistFile<T: Decodable>(at _: AbsolutePath, decoder _: PropertyListDecoder) async throws -> T {
            throw NSError(domain: "Not implemented", code: 0)
        }

        func writeAsPlist(_ _: some Encodable, at _: AbsolutePath) async throws {}
        func writeAsPlist(_ _: some Encodable, at _: AbsolutePath, encoder _: PropertyListEncoder) async throws {}
        func writeAsPlist(
            _ _: some Encodable,
            at _: AbsolutePath,
            encoder _: PropertyListEncoder,
            options _: Set<WritePlistOptions>
        ) async throws {}
        func readJSONFile<T: Decodable>(at _: AbsolutePath) async throws -> T {
            throw NSError(domain: "Not implemented", code: 0)
        }

        func readJSONFile<T: Decodable>(at _: AbsolutePath, decoder _: JSONDecoder) async throws -> T {
            throw NSError(domain: "Not implemented", code: 0)
        }

        func writeAsJSON(_ _: some Encodable, at _: AbsolutePath) async throws {}
        func writeAsJSON(_ _: some Encodable, at _: AbsolutePath, encoder _: JSONEncoder) async throws {}
        func writeAsJSON(
            _ _: some Encodable,
            at _: AbsolutePath,
            encoder _: JSONEncoder,
            options _: Set<WriteJSONOptions>
        ) async throws {}
        func fileSizeInBytes(at _: AbsolutePath) async throws -> Int64? { nil }
        func replace(_ _: AbsolutePath, with _: AbsolutePath) async throws {}
        func copy(_ _: AbsolutePath, to _: AbsolutePath) async throws {}
        func locateTraversingUp(from _: AbsolutePath, relativePath _: RelativePath) async throws -> AbsolutePath? { nil }
        func createSymbolicLink(from _: AbsolutePath, to _: AbsolutePath) async throws {}
        func createSymbolicLink(from _: AbsolutePath, to _: RelativePath) async throws {}
        func resolveSymbolicLink(_ path: AbsolutePath) async throws -> AbsolutePath { path }
        func zipFileOrDirectoryContent(at _: AbsolutePath, to _: AbsolutePath) async throws {}
        func unzip(_ _: AbsolutePath, to _: AbsolutePath) async throws {}
        func contentsOfDirectory(_ _: AbsolutePath) async throws -> [AbsolutePath] { [] }
        func glob(directory _: AbsolutePath, include _: [String]) throws -> AnyThrowingAsyncSequenceable<AbsolutePath> {
            throw NSError(domain: "Not implemented", code: 0)
        }

        func currentWorkingDirectory() async throws -> AbsolutePath {
            try AbsolutePath(validating: "/")
        }

        func fileMetadata(at _: AbsolutePath) async throws -> FileMetadata? { nil }
        func setFileTimes(of _: AbsolutePath, lastAccessDate _: Date?, lastModificationDate _: Date?) async throws {}

        private func isFolder(_ path: AbsolutePath) -> Bool {
            cache[path] == .folder
        }
    }
}

extension WorkspaceStructure.Element {
    static func group(
        _ name: String,
        _ path: AbsolutePath,
        _ contents: [WorkspaceStructure.Element]
    ) -> WorkspaceStructure.Element {
        .group(name: name, path: path, contents: contents)
    }

    static func project(_ path: AbsolutePath) -> WorkspaceStructure.Element {
        .project(path: path)
    }

    static func file(_ path: AbsolutePath) -> WorkspaceStructure.Element {
        .file(path: path)
    }

    static func folderReference(_ path: AbsolutePath) -> WorkspaceStructure.Element {
        .folderReference(path: path)
    }
}
