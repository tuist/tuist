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
        system.swiftlangVersionStub = { "5.4.0" }
        subject = CacheGraphContentHasher(contentHasher: CacheContentHasher())
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
        let project1 = Project.test(path: try temporaryPath().appending(component: "f1"))
        let project2 = Project.test(path: try temporaryPath().appending(component: "f2"))
        let framework1 = makeFramework(project: project1, sources: [source1, source2])
        let framework2 = makeFramework(project: project2, sources: [source2, source1])
        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ],
            targets: [
                project1.path: [
                    framework1.target.name: framework1.target,
                ],
                project2.path: [
                    framework2.target.name: framework2.target,
                ],
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            cacheProfile: .test(),
            cacheOutputType: .framework,
            excludedTargets: []
        )

        // Then
        XCTAssertEqual(contentHash[framework1], contentHash[framework2])
    }

    func test_contentHashes_frameworksWithDifferentSources() throws {
        // Given
        let project1 = Project.test(path: try temporaryPath().appending(component: "f1"))
        let project2 = Project.test(path: try temporaryPath().appending(component: "f2"))
        let framework1 = makeFramework(project: project1, sources: [source1, source2])
        let framework2 = makeFramework(project: project2, sources: [source3, source4])
        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ],
            targets: [
                project1.path: [
                    framework1.target.name: framework1.target,
                ],
                project2.path: [
                    framework2.target.name: framework2.target,
                ],
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            cacheProfile: .test(),
            cacheOutputType: .framework,
            excludedTargets: []
        )

        // Then
        XCTAssertNotEqual(contentHash[framework1], contentHash[framework2])
    }

    func test_contentHashes_hashIsConsistent() throws {
        // Given
        let project1 = Project.test(path: try temporaryPath().appending(component: "f1"))
        let project2 = Project.test(path: try temporaryPath().appending(component: "f2"))
        let framework1 = makeFramework(project: project1, sources: [source1, source2])
        let framework2 = makeFramework(project: project2, sources: [source3, source4])
        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ],
            targets: [
                project1.path: [
                    framework1.target.name: framework1.target,
                ],
                project2.path: [
                    framework2.target.name: framework2.target,
                ],
            ]
        )
        let cacheProfile = TuistGraph.Cache.Profile(name: "Simulator", configuration: "Debug")

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            cacheProfile: cacheProfile,
            cacheOutputType: .framework,
            excludedTargets: []
        )

        // Then
        XCTAssertEqual(contentHash[framework1], "d4631574745e74fc2ab6b7b9cceab088")
        XCTAssertEqual(contentHash[framework2], "86a8f13a091f073b5395eddb452f14da")
    }

    func test_contentHashes_hashChangesWithCacheOutputType() throws {
        // Given
        let project1 = Project.test(path: try temporaryPath().appending(component: "f1"))
        let project2 = Project.test(path: try temporaryPath().appending(component: "f2"))
        let framework1 = makeFramework(project: project1, sources: [source1, source2])
        let framework2 = makeFramework(project: project2, sources: [source3, source4])
        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ],
            targets: [
                project1.path: [
                    framework1.target.name: framework1.target,
                ],
                project2.path: [
                    framework2.target.name: framework2.target,
                ],
            ]
        )

        // When
        let contentFrameworkHash = try subject.contentHashes(
            for: graph,
            cacheProfile: .test(),
            cacheOutputType: .framework,
            excludedTargets: []
        )
        let contentXCFrameworkHash = try subject.contentHashes(
            for: graph,
            cacheProfile: .test(),
            cacheOutputType: .xcframework([.device, .simulator]),
            excludedTargets: []
        )

        // Then
        XCTAssertNotEqual(contentFrameworkHash[framework1], contentXCFrameworkHash[framework1])
        XCTAssertNotEqual(contentFrameworkHash[framework2], contentXCFrameworkHash[framework2])
    }

    // MARK: - Resources

    func test_contentHashes_differentResourceFiles() throws {
        // Given
        let project1 = Project.test(path: try temporaryPath().appending(component: "f1"))
        let project2 = Project.test(path: try temporaryPath().appending(component: "f2"))
        let framework1 = makeFramework(project: project1, resources: [resourceFile1])
        let framework2 = makeFramework(project: project2, resources: [resourceFile2])
        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ],
            targets: [
                project1.path: [
                    framework1.target.name: framework1.target,
                ],
                project2.path: [
                    framework2.target.name: framework2.target,
                ],
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            cacheProfile: .test(),
            cacheOutputType: .framework,
            excludedTargets: []
        )

        // Then
        XCTAssertNotEqual(contentHash[framework1], contentHash[framework2])
    }

    func test_contentHashes_differentResourcesFolderReferences() throws {
        // Given
        let project1 = Project.test(path: try temporaryPath().appending(component: "f1"))
        let project2 = Project.test(path: try temporaryPath().appending(component: "f2"))
        let framework1 = makeFramework(project: project1, resources: [resourceFolderReference1])
        let framework2 = makeFramework(project: project2, resources: [resourceFolderReference2])
        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ],
            targets: [
                project1.path: [
                    framework1.target.name: framework1.target,
                ],
                project2.path: [
                    framework2.target.name: framework2.target,
                ],
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            cacheProfile: .test(),
            cacheOutputType: .framework,
            excludedTargets: []
        )

        // Then
        XCTAssertNotEqual(contentHash[framework1], contentHash[framework2])
    }

    func test_contentHashes_sameResources() throws {
        // Given
        let resources: [ResourceFileElement] = [resourceFile1, resourceFolderReference1]
        let project1 = Project.test(path: try temporaryPath().appending(component: "f1"))
        let project2 = Project.test(path: try temporaryPath().appending(component: "f2"))
        let framework1 = makeFramework(project: project1, resources: resources)
        let framework2 = makeFramework(project: project2, resources: resources)
        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ],
            targets: [
                project1.path: [
                    framework1.target.name: framework1.target,
                ],
                project2.path: [
                    framework2.target.name: framework2.target,
                ],
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            cacheProfile: .test(),
            cacheOutputType: .framework,
            excludedTargets: []
        )

        // Then
        XCTAssertEqual(contentHash[framework1], contentHash[framework2])
    }

    // MARK: - Core Data Models

    func test_contentHashes_differentCoreDataModels() throws {
        // Given
        let project1 = Project.test(path: try temporaryPath().appending(component: "f1"))
        let project2 = Project.test(path: try temporaryPath().appending(component: "f2"))
        let framework1 = makeFramework(project: project1, coreDataModels: [coreDataModel1])
        let framework2 = makeFramework(project: project2, coreDataModels: [coreDataModel2])
        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ],
            targets: [
                project1.path: [
                    framework1.target.name: framework1.target,
                ],
                project2.path: [
                    framework2.target.name: framework2.target,
                ],
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            cacheProfile: .test(),
            cacheOutputType: .framework,
            excludedTargets: []
        )

        // Then
        XCTAssertNotEqual(contentHash[framework1], contentHash[framework2])
    }

    func test_contentHashes_sameCoreDataModels() throws {
        // Given
        let project1 = Project.test(path: try temporaryPath().appending(component: "f1"))
        let project2 = Project.test(path: try temporaryPath().appending(component: "f2"))
        let framework1 = makeFramework(project: project1, coreDataModels: [coreDataModel1])
        let framework2 = makeFramework(project: project2, coreDataModels: [coreDataModel1])
        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ],
            targets: [
                project1.path: [
                    framework1.target.name: framework1.target,
                ],
                project2.path: [
                    framework2.target.name: framework2.target,
                ],
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            cacheProfile: .test(),
            cacheOutputType: .framework,
            excludedTargets: []
        )

        // Then
        XCTAssertEqual(contentHash[framework1], contentHash[framework2])
    }

    // MARK: - Target Actions

    // MARK: - Platform

    func test_contentHashes_differentPlatform() throws {
        // Given
        let project1 = Project.test(path: try temporaryPath().appending(component: "f1"))
        let project2 = Project.test(path: try temporaryPath().appending(component: "f2"))
        let framework1 = makeFramework(project: project1, platform: .iOS)
        let framework2 = makeFramework(project: project2, platform: .macOS)
        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ],
            targets: [
                project1.path: [
                    framework1.target.name: framework1.target,
                ],
                project2.path: [
                    framework2.target.name: framework2.target,
                ],
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            cacheProfile: .test(),
            cacheOutputType: .framework,
            excludedTargets: []
        )

        XCTAssertNotEqual(contentHash[framework1], contentHash[framework2])
    }

    // MARK: - ProductName

    func test_contentHashes_differentProductName() throws {
        // Given
        let project1 = Project.test(path: try temporaryPath().appending(component: "f1"))
        let project2 = Project.test(path: try temporaryPath().appending(component: "f2"))
        let framework1 = makeFramework(project: project1, productName: "1")
        let framework2 = makeFramework(project: project2, productName: "2")
        let graph = Graph.test(
            projects: [
                project1.path: project1,
                project2.path: project2,
            ],
            targets: [
                project1.path: [
                    framework1.target.name: framework1.target,
                ],
                project2.path: [
                    framework2.target.name: framework2.target,
                ],
            ]
        )

        // When
        let contentHash = try subject.contentHashes(
            for: graph,
            cacheProfile: .test(),
            cacheOutputType: .framework,
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
        project: Project,
        platform: Platform = .iOS,
        productName: String? = nil,
        sources: [SourceFile] = [],
        resources: [ResourceFileElement] = [],
        coreDataModels: [CoreDataModel] = [],
        targetScripts: [TargetScript] = []
    ) -> GraphTarget {
        GraphTarget.test(
            path: project.path,
            target: .test(
                platform: platform,
                product: .framework,
                productName: productName,
                sources: sources,
                resources: resources,
                coreDataModels: coreDataModels,
                scripts: targetScripts
            ),
            project: project
        )
    }
}
