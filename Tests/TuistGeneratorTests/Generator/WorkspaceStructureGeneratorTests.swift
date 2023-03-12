import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class WorkspaceStructureGeneratorTests: XCTestCase {
    fileprivate var fileHandler: InMemoryFileHandler!
    var subject: WorkspaceStructureGenerator!

    override func setUp() {
        fileHandler = InMemoryFileHandler()
        subject = WorkspaceStructureGenerator()
    }

    override func tearDown() {
        fileHandler = nil
        subject = nil
    }

    func test_generateStructure_projects() throws {
        // Given
        let xcodeProjPaths = try createFolders([
            "/path/to/workspace/Modules/A/Project.xcodeproj",
            "/path/to/workspace/Modules/B/Project.xcodeproj",
            "/path/to/workspace/Modules/Sub/C/Project.xcodeproj",
            "/path/to/workspace/Modules/Sub/D/Project.xcodeproj",
        ])

        // When
        let structure = subject.generateStructure(
            path: "/path/to/workspace",
            workspace: Workspace.test(),
            xcodeProjPaths: xcodeProjPaths,
            fileHandler: fileHandler
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

    func test_generateStructure_projectsAndFiles() throws {
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
        let structure = subject.generateStructure(
            path: "/path/to/workspace",
            workspace: workspace,
            xcodeProjPaths: xcodeProjPaths,
            fileHandler: fileHandler
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

    func test_generateStructure_folderReferences() throws {
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
        let structure = subject.generateStructure(
            path: "/path/to/workspace",
            workspace: workspace,
            xcodeProjPaths: [],
            fileHandler: fileHandler
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

    func test_generateStructure_collapseDirectories() throws {
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
        let structure = subject.generateStructure(
            path: "/path/to/workspace",
            workspace: workspace,
            xcodeProjPaths: [],
            fileHandler: fileHandler
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

    func test_generateStructure_excludesFolders() throws {
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
        let structure = subject.generateStructure(
            path: "/path/to/workspace",
            workspace: workspace,
            xcodeProjPaths: [],
            fileHandler: fileHandler
        )

        // Then
        XCTAssertEqual(structure.contents, [])
    }

    func test_generateStructure_includesContainerTypes() throws {
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
        let structure = subject.generateStructure(
            path: "/path/to/workspace",
            workspace: workspace,
            xcodeProjPaths: [],
            fileHandler: fileHandler
        )

        // Then
        XCTAssertEqual(structure.contents, [
            .file("/path/to/workspace/Pods.xcodeproj"),
            .file("/path/to/workspace/Testing.playground"),
        ])
    }

    func test_generateStructure_projectsAndFilesOverlap() throws {
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
        let structure = subject.generateStructure(
            path: "/path/to/workspace",
            workspace: workspace,
            xcodeProjPaths: xcodeProjPaths,
            fileHandler: fileHandler
        )

        // Then
        XCTAssertEqual(structure.contents, [
            .group("Modules", "/path/to/workspace/Modules", [
                .project("/path/to/workspace/Modules/A/Project.xcodeproj"),
                .folderReference("/path/to/workspace/Modules/A"),
            ]),
        ])
    }

    func test_generateStructure_projectsAndNestedFiles() throws {
        // Given
        let xcodeProjPaths = try createFolders([
            "/path/to/workspace/Modules/A/Project.xcodeproj",
        ])

        let files = try createFiles([
            "/path/to/workspace/Modules/A/README.md",
        ])

        let workspace = Workspace.test(additionalFiles: files.map { .file(path: $0) })

        // When
        let structure = subject.generateStructure(
            path: "/path/to/workspace",
            workspace: workspace,
            xcodeProjPaths: xcodeProjPaths,
            fileHandler: fileHandler
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

    // MARK: - Helpers

    @discardableResult
    func createFolders(_ folders: [String]) throws -> [AbsolutePath] {
        let paths = folders.map { try! AbsolutePath(validating: $0) }
        try paths.forEach {
            try fileHandler.createFolder($0)
        }
        return paths
    }

    @discardableResult
    func createFiles(_ files: [String]) throws -> [AbsolutePath] {
        let paths = files.map { try! AbsolutePath(validating: $0) }
        try paths.forEach {
            try fileHandler.touch($0)
        }
        return paths
    }

    fileprivate class InMemoryFileHandler: FileHandling {
        func temporaryDirectory() throws -> AbsolutePath {
            currentPath
        }

        private enum Node {
            case file
            case folder
        }

        private var cache: [AbsolutePath: Node] = [:]

        var currentPath: AbsolutePath = "/"
        var homeDirectory: AbsolutePath = "/"

        func replace(_: AbsolutePath, with _: AbsolutePath) throws {}

        func exists(_ path: AbsolutePath) -> Bool {
            cache[path] != nil
        }

        func move(from _: AbsolutePath, to _: AbsolutePath) throws {}

        func copy(from _: AbsolutePath, to _: AbsolutePath) throws {}

        func readTextFile(_: AbsolutePath) throws -> String {
            ""
        }

        func readFile(_: AbsolutePath) throws -> Data {
            Data()
        }

        func readPlistFile<T>(_: AbsolutePath) throws -> T where T: Decodable {
            try JSONDecoder().decode(T.self, from: Data())
        }

        func determineTemporaryDirectory() throws -> AbsolutePath {
            currentPath
        }

        func inTemporaryDirectory(_: (AbsolutePath) throws -> Void) throws {}
        func inTemporaryDirectory(removeOnCompletion _: Bool, _: (AbsolutePath) throws -> Void) throws {}
        func inTemporaryDirectory<Result>(_ closure: (AbsolutePath) throws -> Result) throws -> Result {
            try closure(currentPath)
        }

        func inTemporaryDirectory<Result>(
            removeOnCompletion _: Bool,
            _ closure: (AbsolutePath) throws -> Result
        ) throws -> Result {
            try closure(currentPath)
        }

        func inTemporaryDirectory(_: @escaping (AbsolutePath) async throws -> Void) async throws {}

        func glob(_: AbsolutePath, glob _: String) -> [AbsolutePath] {
            []
        }

        func throwingGlob(_: AbsolutePath, glob _: String) throws -> [AbsolutePath] {
            []
        }

        func resolveSymlinks(_ path: AbsolutePath) -> AbsolutePath {
            path
        }

        func fileAttributes(at _: AbsolutePath) throws -> [FileAttributeKey: Any] {
            [:]
        }

        func write(_: String, path _: AbsolutePath, atomically _: Bool) throws {
            // Do nothing
        }

        func createFolder(_ path: AbsolutePath) throws {
            var pathSoFar = try AbsolutePath(validating: "/")
            for component in path.components.dropFirst() {
                pathSoFar = pathSoFar.appending(component: component)
                cache[pathSoFar] = .folder
            }
        }

        func linkFile(atPath _: AbsolutePath, toPath: AbsolutePath) throws {
            try touch(toPath)
        }

        func delete(_ path: AbsolutePath) throws {
            cache.removeValue(forKey: path)
        }

        func isFolder(_ path: AbsolutePath) -> Bool {
            cache[path] == .folder
        }

        func locateDirectoryTraversingParents(from _: AbsolutePath, path _: String) -> AbsolutePath? {
            nil
        }

        func touch(_ path: AbsolutePath) throws {
            let parent = path.parentDirectory
            try createFolder(parent)
            cache[path] = .file
        }

        func locateDirectory(_: String, traversingFrom _: AbsolutePath) -> AbsolutePath? {
            nil
        }

        func contentsOfDirectory(_: AbsolutePath) throws -> [AbsolutePath] {
            []
        }

        func filesAndDirectoriesContained(in _: AbsolutePath) -> [AbsolutePath]? {
            nil
        }

        func ls(_: AbsolutePath) throws -> [AbsolutePath] {
            []
        }

        func urlSafeBase64MD5(path _: AbsolutePath) throws -> String {
            "urlSafeBase64MD5"
        }

        func fileSize(path _: AbsolutePath) throws -> UInt64 {
            0
        }

        func changeExtension(path: AbsolutePath, to newExtension: String) throws -> AbsolutePath {
            path.removingLastComponent().appending(component: "\(path.basenameWithoutExt).\(newExtension)")
        }

        func zipItem(at _: AbsolutePath, to _: AbsolutePath) throws {}

        func unzipItem(at _: AbsolutePath, to _: AbsolutePath) throws {}
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
