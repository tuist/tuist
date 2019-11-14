import Basic
import TuistSupport
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

class WorkspaceStructureGeneratorTests: XCTestCase {
    fileprivate var fileHandler: InMemoryFileHandler!
    var subject: WorkspaceStructureGenerator!

    override func setUp() {
        fileHandler = InMemoryFileHandler()
        subject = WorkspaceStructureGenerator()
    }

    override func tearDown() {
        fileHandler = nil
    }

    func test_generateStructure_projects() throws {
        // Given
        let projects = try createFolders([
            "/path/to/workspace/Modules/A",
            "/path/to/workspace/Modules/B",
            "/path/to/workspace/Modules/Sub/C",
            "/path/to/workspace/Modules/Sub/D",
        ])

        // When
        let structure = subject.generateStructure(path: "/path/to/workspace",
                                                  workspace: Workspace.test(projects: projects),
                                                  fileHandler: fileHandler)

        // Then
        XCTAssertEqual(structure.contents, [
            .group("Modules", "/path/to/workspace/Modules", [
                .project("/path/to/workspace/Modules/A"),
                .project("/path/to/workspace/Modules/B"),
                .group("Sub", "/path/to/workspace/Modules/Sub", [
                    .project("/path/to/workspace/Modules/Sub/C"),
                    .project("/path/to/workspace/Modules/Sub/D"),
                ]),
            ]),
        ])
    }

    func test_generateStructure_projectsAndFiles() throws {
        // Given
        let projects = try createFolders([
            "/path/to/workspace/Modules/A",
            "/path/to/workspace/Modules/B",
        ])

        let files = try createFiles([
            "/path/to/workspace/Documentation/README.md",
            "/path/to/workspace/Documentation/setup/usage.md",
            "/path/to/workspace/Documentation/generate/guide.md",
            "/path/to/workspace/README.md",
        ])

        let workspace = Workspace.test(projects: projects,
                                       additionalFiles: files.map { .file(path: $0) })

        // When
        let structure = subject.generateStructure(path: "/path/to/workspace",
                                                  workspace: workspace,
                                                  fileHandler: fileHandler)

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
                .project("/path/to/workspace/Modules/A"),
                .project("/path/to/workspace/Modules/B"),
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
        let structure = subject.generateStructure(path: "/path/to/workspace",
                                                  workspace: workspace,
                                                  fileHandler: fileHandler)

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
        let workspace = Workspace.test(additionalFiles: paths.map { .file(path: AbsolutePath($0)) })

        // When
        let structure = subject.generateStructure(path: "/path/to/workspace",
                                                  workspace: workspace,
                                                  fileHandler: fileHandler)

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
        let workspace = Workspace.test(additionalFiles: paths.map { .file(path: AbsolutePath($0)) })

        // When
        let structure = subject.generateStructure(path: "/path/to/workspace",
                                                  workspace: workspace,
                                                  fileHandler: fileHandler)

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
        let workspace = Workspace.test(additionalFiles: paths.map { .file(path: AbsolutePath($0)) })

        // When
        let structure = subject.generateStructure(path: "/path/to/workspace",
                                                  workspace: workspace,
                                                  fileHandler: fileHandler)

        // Then
        XCTAssertEqual(structure.contents, [
            .file("/path/to/workspace/Pods.xcodeproj"),
            .file("/path/to/workspace/Testing.playground"),
        ])
    }

    func test_generateStructure_projectsAndFilesOverlap() throws {
        // Given
        let projects = try createFolders([
            "/path/to/workspace/Modules/A",
        ])

        let files: [FileElement] = [
            .folderReference(path: "/path/to/workspace/Modules/A"),
        ]
        let workspace = Workspace.test(projects: projects,
                                       additionalFiles: files)

        // When
        let structure = subject.generateStructure(path: "/path/to/workspace",
                                                  workspace: workspace,
                                                  fileHandler: fileHandler)

        // Then
        XCTAssertEqual(structure.contents, [
            .group("Modules", "/path/to/workspace/Modules", [
                .project("/path/to/workspace/Modules/A"),
                .folderReference("/path/to/workspace/Modules/A"),
            ]),
        ])
    }

    func test_generateStructure_projectsAndNestedFiles() throws {
        // Given
        let projects = try createFolders([
            "/path/to/workspace/Modules/A",
        ])

        let files = try createFiles([
            "/path/to/workspace/Modules/A/README.md",
        ])

        let workspace = Workspace.test(projects: projects,
                                       additionalFiles: files.map { .file(path: $0) })

        // When
        let structure = subject.generateStructure(path: "/path/to/workspace",
                                                  workspace: workspace,
                                                  fileHandler: fileHandler)

        // Then
        XCTAssertEqual(structure.contents, [
            .group("Modules", "/path/to/workspace/Modules", [
                .project("/path/to/workspace/Modules/A"),
                .group("A", "/path/to/workspace/Modules/A", [
                    .file("/path/to/workspace/Modules/A/README.md"),
                ]),
            ]),
        ])
    }

    // MARK: - Helpers

    @discardableResult
    func createFolders(_ folders: [String]) throws -> [AbsolutePath] {
        let paths = folders.map { AbsolutePath($0) }
        try paths.forEach {
            try fileHandler.createFolder($0)
        }
        return paths
    }

    @discardableResult
    func createFiles(_ files: [String]) throws -> [AbsolutePath] {
        let paths = files.map { AbsolutePath($0) }
        try paths.forEach {
            try fileHandler.touch($0)
        }
        return paths
    }

    fileprivate class InMemoryFileHandler: FileHandling {
        private enum Node {
            case file
            case folder
        }

        private var cache: [AbsolutePath: Node] = [:]

        var currentPath: AbsolutePath = "/"

        func replace(_: AbsolutePath, with _: AbsolutePath) throws {}

        func exists(_ path: AbsolutePath) -> Bool {
            return cache[path] != nil
        }

        func move(from _: AbsolutePath, to _: AbsolutePath) throws {}

        func copy(from _: AbsolutePath, to _: AbsolutePath) throws {}

        func readTextFile(_: AbsolutePath) throws -> String {
            return ""
        }

        func inTemporaryDirectory(_: (AbsolutePath) throws -> Void) throws {}

        func glob(_: AbsolutePath, glob _: String) -> [AbsolutePath] {
            return []
        }

        func write(_: String, path _: AbsolutePath, atomically _: Bool) throws {
            // Do nothing
        }

        func createFolder(_ path: AbsolutePath) throws {
            var pathSoFar = AbsolutePath("/")
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
            return cache[path] == .folder
        }

        func locateDirectoryTraversingParents(from _: AbsolutePath, path _: String) -> AbsolutePath? {
            return nil
        }

        func touch(_ path: AbsolutePath) throws {
            let parent = path.parentDirectory
            try createFolder(parent)
            cache[path] = .file
        }

        func locateDirectory(_: String, traversingFrom _: AbsolutePath) -> AbsolutePath? {
            return nil
        }

        func ls(_: AbsolutePath) throws -> [AbsolutePath] {
            return []
        }
    }
}

extension WorkspaceStructure.Element {
    static func group(_ name: String,
                      _ path: AbsolutePath,
                      _ contents: [WorkspaceStructure.Element]) -> WorkspaceStructure.Element {
        return .group(name: name, path: path, contents: contents)
    }

    static func project(_ path: AbsolutePath) -> WorkspaceStructure.Element {
        return .project(path: path)
    }

    static func file(_ path: AbsolutePath) -> WorkspaceStructure.Element {
        return .file(path: path)
    }

    static func folderReference(_ path: AbsolutePath) -> WorkspaceStructure.Element {
        return .folderReference(path: path)
    }
}
