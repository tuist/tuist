import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistCache
@testable import TuistCore
@testable import TuistSupportTesting

final class ContentHashingIntegrationTests: TuistTestCase {
    var subject: GraphContentHasher!
    var temporaryDirectoryPath: String!
    var source1: SourceFile!
    var source2: SourceFile!
    var source3: SourceFile!
    var source4: SourceFile!
    var resourceFile1: FileElement!
    var resourceFile2: FileElement!
    var resourceFolderReference1: FileElement!
    var resourceFolderReference2: FileElement!
    var coreDataModel1: CoreDataModel!
    var coreDataModel2: CoreDataModel!

    override func setUp() {
        super.setUp()
        do {
            let temporaryDirectoryPath = try temporaryPath()
            source1 = try createTemporarySourceFile(on: temporaryDirectoryPath, name: "1", content: "1")
            source2 = try createTemporarySourceFile(on: temporaryDirectoryPath, name: "2", content: "2")
            source3 = try createTemporarySourceFile(on: temporaryDirectoryPath, name: "3", content: "3")
            source4 = try createTemporarySourceFile(on: temporaryDirectoryPath, name: "4", content: "4")
            resourceFile1 = try createTemporaryResourceFile(on: temporaryDirectoryPath, name: "r1", content: "r1")
            resourceFile2 = try createTemporaryResourceFile(on: temporaryDirectoryPath, name: "r2", content: "r2")
            resourceFolderReference1 = try createTemporaryResourceFolderReference(on: temporaryDirectoryPath, name: "rf1", content: "rf1")
            resourceFolderReference2 = try createTemporaryResourceFolderReference(on: temporaryDirectoryPath, name: "rf2", content: "rf2")
            _ = try createTemporarySourceFile(on: temporaryDirectoryPath, name: "CoreDataModel1", content: "cd1")
            _ = try createTemporarySourceFile(on: temporaryDirectoryPath, name: "CoreDataModel2", content: "cd2")
            _ = try createTemporarySourceFile(on: temporaryDirectoryPath, name: "Info.plist", content: "plist")
            coreDataModel1 = CoreDataModel(path: temporaryDirectoryPath.appending(component: "CoreDataModel1"), versions: [], currentVersion: "1")
            coreDataModel2 = CoreDataModel(path: temporaryDirectoryPath.appending(component: "CoreDataModel2"), versions: [], currentVersion: "2")
        } catch {
            XCTFail("Error while creating files for stub project")
        }
        subject = GraphContentHasher(contentHasher: CacheContentHasher())
    }

    override func tearDown() {
        subject = nil
        source1 = nil
        source2 = nil
        source3 = nil
        source4 = nil
        resourceFile1 = nil
        resourceFile2 = nil
        resourceFolderReference1 = nil
        resourceFolderReference2 = nil
        coreDataModel1 = nil
        coreDataModel2 = nil
        super.tearDown()
    }

    // MARK: - Sources

    func test_contentHashes_frameworksWithSameSources() throws {
        // Given
        let temporaryDirectoryPath = try temporaryPath()
        let framework1 = makeFramework(named: "f1", sources: [source1, source2])
        let framework2 = makeFramework(named: "f2", sources: [source2, source1])
        let graph = Graph.test(targets: [
            temporaryDirectoryPath: [framework1, framework2],
        ])

        // When
        let contentHash = try subject.contentHashes(for: graph, cacheOutputType: .framework)

        // Then
        XCTAssertEqual(contentHash[framework1], contentHash[framework2])
    }

    func test_contentHashes_frameworksWithDifferentSources() throws {
        // Given
        let temporaryDirectoryPath = try temporaryPath()
        let framework1 = makeFramework(named: "f1", sources: [source1, source2])
        let framework2 = makeFramework(named: "f2", sources: [source3, source4])
        let graph = Graph.test(targets: [
            temporaryDirectoryPath: [framework1, framework2],
        ])

        // When
        let contentHash = try subject.contentHashes(for: graph, cacheOutputType: .framework)

        // Then
        XCTAssertNotEqual(contentHash[framework1], contentHash[framework2])
    }

    func test_contentHashes_hashIsConsistent() throws {
        // Given
        let temporaryDirectoryPath = try temporaryPath()
        let framework1 = makeFramework(named: "f1", sources: [source1, source2])
        let framework2 = makeFramework(named: "f2", sources: [source3, source4])
        let graph = Graph.test(targets: [
            temporaryDirectoryPath: [framework1, framework2],
        ])

        // When
        let contentHash = try subject.contentHashes(for: graph, cacheOutputType: .framework)

        // Then
        XCTAssertEqual(contentHash[framework1], "5627efce7c307c2bef2b1c4a1e2673c9")
        XCTAssertEqual(contentHash[framework2], "d593a9717a2d197ae5906096dd678a46")
    }

    func test_contentHashes_hashChangesWithCacheOutputType() throws {
        // Given
        let temporaryDirectoryPath = try temporaryPath()
        let framework1 = makeFramework(named: "f1", sources: [source1, source2])
        let framework2 = makeFramework(named: "f2", sources: [source3, source4])
        let graph = Graph.test(targets: [
            temporaryDirectoryPath: [framework1, framework2],
        ])

        // When
        let contentFrameworkHash = try subject.contentHashes(for: graph, cacheOutputType: .framework)
        let contentXCFrameworkHash = try subject.contentHashes(for: graph, cacheOutputType: .xcframework)

        // Then
        XCTAssertNotEqual(contentFrameworkHash[framework1], contentXCFrameworkHash[framework1])
        XCTAssertNotEqual(contentFrameworkHash[framework2], contentXCFrameworkHash[framework2])
    }

    // MARK: - Resources

    func test_contentHashes_differentResourceFiles() throws {
        // Given
        let temporaryDirectoryPath = try temporaryPath()
        let framework1 = makeFramework(named: "f1", resources: [resourceFile1])
        let framework2 = makeFramework(named: "f2", resources: [resourceFile2])
        let graph = Graph.test(targets: [
            temporaryDirectoryPath: [framework1, framework2],
        ])

        // When
        let contentHash = try subject.contentHashes(for: graph, cacheOutputType: .framework)

        // Then
        XCTAssertNotEqual(contentHash[framework1], contentHash[framework2])
    }

    func test_contentHashes_differentResourcesFolderReferences() throws {
        // Given
        let temporaryDirectoryPath = try temporaryPath()
        let framework1 = makeFramework(named: "f1", resources: [resourceFolderReference1])
        let framework2 = makeFramework(named: "f2", resources: [resourceFolderReference2])
        let graph = Graph.test(targets: [
            temporaryDirectoryPath: [framework1, framework2],
        ])

        // When
        let contentHash = try subject.contentHashes(for: graph, cacheOutputType: .framework)

        // Then
        XCTAssertNotEqual(contentHash[framework1], contentHash[framework2])
    }

    func test_contentHashes_sameResources() throws {
        // Given
        let temporaryDirectoryPath = try temporaryPath()
        let resources: [FileElement] = [resourceFile1, resourceFolderReference1]
        let framework1 = makeFramework(named: "f1", resources: resources)
        let framework2 = makeFramework(named: "f2", resources: resources)
        let graph = Graph.test(targets: [
            temporaryDirectoryPath: [framework1, framework2],
        ])

        // When
        let contentHash = try subject.contentHashes(for: graph, cacheOutputType: .framework)

        // Then
        XCTAssertEqual(contentHash[framework1], contentHash[framework2])
    }

    // MARK: - Core Data Models

    func test_contentHashes_differentCoreDataModels() throws {
        // Given
        let temporaryDirectoryPath = try temporaryPath()
        let framework1 = makeFramework(named: "f1", coreDataModels: [coreDataModel1])
        let framework2 = makeFramework(named: "f2", coreDataModels: [coreDataModel2])
        let graph = Graph.test(targets: [
            temporaryDirectoryPath: [framework1, framework2],
        ])

        // When
        let contentHash = try subject.contentHashes(for: graph, cacheOutputType: .framework)

        // Then
        XCTAssertNotEqual(contentHash[framework1], contentHash[framework2])
    }

    func test_contentHashes_sameCoreDataModels() throws {
        // Given
        let temporaryDirectoryPath = try temporaryPath()
        let framework1 = makeFramework(named: "f1", coreDataModels: [coreDataModel1])
        let framework2 = makeFramework(named: "f2", coreDataModels: [coreDataModel1])
        let graph = Graph.test(targets: [
            temporaryDirectoryPath: [framework1, framework2],
        ])

        // When
        let contentHash = try subject.contentHashes(for: graph, cacheOutputType: .framework)

        // Then
        XCTAssertEqual(contentHash[framework1], contentHash[framework2])
    }

    // MARK: - Target Actions

    // MARK: - Platform

    func test_contentHashes_differentPlatform() throws {
        // Given
        let temporaryDirectoryPath = try temporaryPath()
        let framework1 = makeFramework(named: "f1", platform: .iOS)
        let framework2 = makeFramework(named: "f2", platform: .macOS)
        let graph = Graph.test(targets: [
            temporaryDirectoryPath: [framework1, framework2],
        ])

        // When
        let contentHash = try subject.contentHashes(for: graph, cacheOutputType: .framework)

        XCTAssertNotEqual(contentHash[framework1], contentHash[framework2])
    }

    // MARK: - ProductName

    func test_contentHashes_differentProductName() throws {
        // Given
        let temporaryDirectoryPath = try temporaryPath()
        let framework1 = makeFramework(named: "f1", productName: "1")
        let framework2 = makeFramework(named: "f2", productName: "2")
        let graph = Graph.test(targets: [
            temporaryDirectoryPath: [framework1, framework2],
        ])

        // When
        let contentHash = try subject.contentHashes(for: graph, cacheOutputType: .framework)

        XCTAssertNotEqual(contentHash[framework1], contentHash[framework2])
    }

    // MARK: - Private helpers

    private func createTemporarySourceFile(on temporaryDirectoryPath: AbsolutePath, name: String, content: String) throws -> SourceFile {
        let filePath = temporaryDirectoryPath.appending(component: name)
        try FileHandler.shared.touch(filePath)
        try FileHandler.shared.write(content, path: filePath, atomically: true)
        return SourceFile(path: filePath, compilerFlags: nil)
    }

    private func createTemporaryResourceFile(on temporaryDirectoryPath: AbsolutePath, name: String, content: String) throws -> FileElement {
        let filePath = temporaryDirectoryPath.appending(component: name)
        try FileHandler.shared.touch(filePath)
        try FileHandler.shared.write(content, path: filePath, atomically: true)
        return FileElement.file(path: filePath)
    }

    private func createTemporaryResourceFolderReference(on temporaryDirectoryPath: AbsolutePath, name: String, content: String) throws -> FileElement {
        let filePath = temporaryDirectoryPath.appending(component: name)
        try FileHandler.shared.touch(filePath)
        try FileHandler.shared.write(content, path: filePath, atomically: true)
        return FileElement.folderReference(path: filePath)
    }

    private func makeFramework(named: String,
                               platform: Platform = .iOS,
                               productName: String? = nil,
                               sources: [SourceFile] = [],
                               resources: [FileElement] = [],
                               coreDataModels: [CoreDataModel] = [],
                               targetActions: [TargetAction] = []) -> TargetNode
    {
        TargetNode.test(
            project: .test(path: AbsolutePath("/test/\(named)")),
            target: .test(platform: platform,
                          product: .framework,
                          productName: productName,
                          sources: sources,
                          resources: resources,
                          coreDataModels: coreDataModels,
                          actions: targetActions)
        )
    }
}
