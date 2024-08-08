import Foundation
import MockableTest
import Path
import struct TSCUtility.Version
import TuistCore
import TuistHasher
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistCache

final class ContentHashingIntegrationTests: TuistUnitTestCase {
    var subject: CacheGraphContentHasher!
    var temporaryDirectoryPath: String!
    var source1: SourceFile!
    var source2: SourceFile!
    var source3: SourceFile!
    var source4: SourceFile!
    var resourceFile1: ResourceFileElement!
    var resourceFile2: ResourceFileElement!
    var resourceFolderReference1: ResourceFileElement!
    var resourceFolderReference2: ResourceFileElement!
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
            resourceFolderReference1 = try createTemporaryResourceFolderReference(
                on: temporaryDirectoryPath,
                name: "rf1",
                content: "rf1"
            )
            resourceFolderReference2 = try createTemporaryResourceFolderReference(
                on: temporaryDirectoryPath,
                name: "rf2",
                content: "rf2"
            )
            _ = try createTemporarySourceFile(on: temporaryDirectoryPath, name: "CoreDataModel1", content: "cd1")
            _ = try createTemporarySourceFile(on: temporaryDirectoryPath, name: "CoreDataModel2", content: "cd2")
            _ = try createTemporarySourceFile(on: temporaryDirectoryPath, name: "Info.plist", content: "plist")
            coreDataModel1 = CoreDataModel(
                path: temporaryDirectoryPath.appending(component: "CoreDataModel1"),
                versions: [],
                currentVersion: "1"
            )
            coreDataModel2 = CoreDataModel(
                path: temporaryDirectoryPath.appending(component: "CoreDataModel2"),
                versions: [],
                currentVersion: "2"
            )
        } catch {
            XCTFail("Error while creating files for stub project")
        }
        given(swiftVersionProvider).swiftlangVersion().willReturn("5.4.0")
        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 3, 0))
        subject = CacheGraphContentHasher(contentHasher: CachedContentHasher())
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
        let framework1Target = makeFramework(sources: [source1, source2])
        let framework2Target = makeFramework(sources: [source2, source1])
        let project1 = Project.test(
            path: try temporaryPath().appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: try temporaryPath().appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            configuration: "Debug",
            config: .test(),
            excludedTargets: []
        )

        // Then
        XCTAssertEqual(contentHash[framework1], contentHash[framework2])
    }

    func test_contentHashes_frameworksWithDifferentSources() throws {
        // Given
        let framework1Target = makeFramework(sources: [source1, source2])
        let framework2Target = makeFramework(sources: [source3, source4])
        let project1 = Project.test(
            path: try temporaryPath().appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: try temporaryPath().appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            configuration: "Debug",
            config: .test(),
            excludedTargets: []
        )

        // Then
        XCTAssertNotEqual(contentHash[framework1], contentHash[framework2])
    }

    func test_contentHashes_hashIsConsistent() throws {
        // Given
        let framework1Target = makeFramework(sources: [source1, source2])
        let framework2Target = makeFramework(sources: [source3, source4])
        let project1 = Project.test(
            path: try temporaryPath().appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: try temporaryPath().appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            configuration: "Debug",
            config: .test(),
            excludedTargets: []
        )

        // Then
        XCTAssertEqual(contentHash[framework1], "ed446c23f3327663c85968146cf9bc8b")
        XCTAssertEqual(contentHash[framework2], "856dc2d5a7df61c597f53147ab8fa5f8")
    }

    // MARK: - Resources

    func test_contentHashes_differentResourceFiles() throws {
        // Given
        let framework1Target = makeFramework(resources: .init([resourceFile1]))
        let framework2Target = makeFramework(resources: .init([resourceFile2]))
        let project1 = Project.test(
            path: try temporaryPath().appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: try temporaryPath().appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            configuration: "Debug",
            config: .test(),
            excludedTargets: []
        )

        // Then
        XCTAssertNotEqual(contentHash[framework1], contentHash[framework2])
    }

    func test_contentHashes_differentResourcesFolderReferences() throws {
        // Given
        let framework1Target = makeFramework(resources: .init([resourceFolderReference1]))
        let framework2Target = makeFramework(resources: .init([resourceFolderReference2]))
        let project1 = Project.test(
            path: try temporaryPath().appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: try temporaryPath().appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            configuration: "Debug",
            config: .test(),
            excludedTargets: []
        )

        // Then
        XCTAssertNotEqual(contentHash[framework1], contentHash[framework2])
    }

    func test_contentHashes_sameResources() throws {
        // Given
        let resources: ResourceFileElements = .init([resourceFile1, resourceFolderReference1])
        let framework1Target = makeFramework(resources: resources)
        let framework2Target = makeFramework(resources: resources)
        let project1 = Project.test(
            path: try temporaryPath().appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: try temporaryPath().appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            configuration: "Debug",
            config: .test(),
            excludedTargets: []
        )

        // Then
        XCTAssertEqual(contentHash[framework1], contentHash[framework2])
    }

    // MARK: - Core Data Models

    func test_contentHashes_differentCoreDataModels() throws {
        // Given
        let framework1Target = makeFramework(coreDataModels: [coreDataModel1])
        let framework2Target = makeFramework(coreDataModels: [coreDataModel2])
        let project1 = Project.test(
            path: try temporaryPath().appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: try temporaryPath().appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            configuration: "Debug",
            config: .test(),
            excludedTargets: []
        )

        // Then
        XCTAssertNotEqual(contentHash[framework1], contentHash[framework2])
    }

    func test_contentHashes_sameCoreDataModels() throws {
        // Given
        let framework1Target = makeFramework(coreDataModels: [coreDataModel1])
        let framework2Target = makeFramework(coreDataModels: [coreDataModel1])
        let project1 = Project.test(
            path: try temporaryPath().appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: try temporaryPath().appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            configuration: "Debug",
            config: .test(),
            excludedTargets: []
        )

        // Then
        XCTAssertEqual(contentHash[framework1], contentHash[framework2])
    }

    // MARK: - Target Actions

    // MARK: - Platform

    func test_contentHashes_differentPlatform() throws {
        // Given
        let framework1Target = makeFramework(platform: .iOS)
        let framework2Target = makeFramework(platform: .macOS)
        let project1 = Project.test(
            path: try temporaryPath().appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: try temporaryPath().appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            configuration: "Debug",
            config: .test(),
            excludedTargets: []
        )

        XCTAssertNotEqual(contentHash[framework1], contentHash[framework2])
    }

    // MARK: - ProductName

    func test_contentHashes_differentProductName() throws {
        // Given
        let framework1Target = makeFramework(productName: "1")
        let framework2Target = makeFramework(productName: "2")
        let project1 = Project.test(
            path: try temporaryPath().appending(component: "f1"),
            settings: .default,
            targets: [framework1Target]
        )
        let project2 = Project.test(
            path: try temporaryPath().appending(component: "f2"),
            settings: .default,
            targets: [framework2Target]
        )
        let framework1 = GraphTarget(path: project1.path, target: framework1Target, project: project1)
        let framework2 = GraphTarget(path: project2.path, target: framework2Target, project: project2)

        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            configuration: "Debug",
            config: .test(),
            excludedTargets: []
        )

        XCTAssertNotEqual(contentHash[framework1], contentHash[framework2])
    }

    // MARK: - Private helpers

    private func createTemporarySourceFile(
        on temporaryDirectoryPath: AbsolutePath,
        name: String,
        content: String
    ) throws -> SourceFile {
        let filePath = temporaryDirectoryPath.appending(component: name)
        try FileHandler.shared.touch(filePath)
        try FileHandler.shared.write(content, path: filePath, atomically: true)
        return SourceFile(path: filePath, compilerFlags: nil)
    }

    private func createTemporaryResourceFile(
        on temporaryDirectoryPath: AbsolutePath,
        name: String,
        content: String
    ) throws -> ResourceFileElement {
        let filePath = temporaryDirectoryPath.appending(component: name)
        try FileHandler.shared.touch(filePath)
        try FileHandler.shared.write(content, path: filePath, atomically: true)
        return ResourceFileElement.file(path: filePath)
    }

    private func createTemporaryResourceFolderReference(
        on temporaryDirectoryPath: AbsolutePath,
        name: String,
        content: String
    ) throws -> ResourceFileElement {
        let filePath = temporaryDirectoryPath.appending(component: name)
        try FileHandler.shared.touch(filePath)
        try FileHandler.shared.write(content, path: filePath, atomically: true)
        return ResourceFileElement.folderReference(path: filePath)
    }

    private func makeFramework(
        platform: Platform = .iOS,
        productName: String? = nil,
        sources: [SourceFile] = [],
        resources: ResourceFileElements = .init([]),
        coreDataModels: [CoreDataModel] = [],
        targetScripts: [TargetScript] = []
    ) -> Target {
        .test(
            platform: platform,
            product: .framework,
            productName: productName,
            sources: sources,
            resources: resources,
            coreDataModels: coreDataModels,
            scripts: targetScripts
        )
    }
}
