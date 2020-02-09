import Basic
import Foundation
import TuistCore
import TuistCoreTesting
import TuistSupport
import XCTest

@testable import TuistCache
@testable import TuistSupportTesting

final class ContentHashingIntegrationTests: TuistTestCase {
    var subject: GraphContentHasher!

    override func setUp() {
        super.setUp()
        subject = GraphContentHasher()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_contentHashes_frameworksWithSameSources() throws {
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)

        let temporaryDirectoryPath = try temporaryPath()
        let source1 = try createTemporaryFile(on: temporaryDirectoryPath, name: "1", content: "1")
        let source2 = try createTemporaryFile(on: temporaryDirectoryPath, name: "2", content: "2")
        let framework1 = makeFramework(named: "f1", withSources: [source1, source2])
        let framework2 = makeFramework(named: "f2", withSources: [source1, source2])
        cache.add(targetNode: framework1)
        cache.add(targetNode: framework2)

        let contentHashes = try subject.contentHashes(for: graph)

        XCTAssertNotNil(contentHashes[framework1])
        XCTAssertNotNil(contentHashes[framework2])
        XCTAssertEqual(contentHashes[framework1], contentHashes[framework2])
    }

    func test_contentHashes_frameworksWithDifferentSources() throws {
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)

        let temporaryDirectoryPath = try temporaryPath()
        let source1 = try createTemporaryFile(on: temporaryDirectoryPath, name: "1", content: "1")
        let source2 = try createTemporaryFile(on: temporaryDirectoryPath, name: "2", content: "2")
        let source3 = try createTemporaryFile(on: temporaryDirectoryPath, name: "3", content: "3")
        let source4 = try createTemporaryFile(on: temporaryDirectoryPath, name: "4", content: "4")
        let framework1 = makeFramework(named: "f1", withSources: [source1, source2])
        let framework2 = makeFramework(named: "f2", withSources: [source3, source4])
        cache.add(targetNode: framework1)
        cache.add(targetNode: framework2)

        let contentHashes = try subject.contentHashes(for: graph)

        XCTAssertNotNil(contentHashes[framework1])
        XCTAssertNotNil(contentHashes[framework2])
        XCTAssertNotEqual(contentHashes[framework1], contentHashes[framework2])
    }

    func test_contentHashes_frameworksWithSameSources_differentPlatform() throws {
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)

        let temporaryDirectoryPath = try temporaryPath()
        let source1 = try createTemporaryFile(on: temporaryDirectoryPath, name: "1", content: "1")
        let source2 = try createTemporaryFile(on: temporaryDirectoryPath, name: "2", content: "2")
        let framework1 = makeFramework(named: "f1", platform: .iOS, withSources: [source1, source2])
        let framework2 = makeFramework(named: "f2", platform: .macOS, withSources: [source1, source2])
        cache.add(targetNode: framework1)
        cache.add(targetNode: framework2)

        let contentHashes = try subject.contentHashes(for: graph)

        XCTAssertNotEqual(contentHashes[framework1], contentHashes[framework2])
    }

    func test_contentHashes_frameworksWithSameSources_differentProductName() throws {
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)

        let temporaryDirectoryPath = try temporaryPath()
        let source1 = try createTemporaryFile(on: temporaryDirectoryPath, name: "1", content: "1")
        let source2 = try createTemporaryFile(on: temporaryDirectoryPath, name: "2", content: "2")
        let framework1 = makeFramework(named: "f1", productName: "1", withSources: [source1, source2])
        let framework2 = makeFramework(named: "f2", productName: "2", withSources: [source1, source2])
        cache.add(targetNode: framework1)
        cache.add(targetNode: framework2)

        let contentHashes = try subject.contentHashes(for: graph)

        XCTAssertNotEqual(contentHashes[framework1], contentHashes[framework2])
    }

    func test_contentHashes_hashIsConsistent() throws {
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)

        let temporaryDirectoryPath = try temporaryPath()
        let source1 = try createTemporaryFile(on: temporaryDirectoryPath, name: "1", content: "1")
        let source2 = try createTemporaryFile(on: temporaryDirectoryPath, name: "2", content: "2")
        let source3 = try createTemporaryFile(on: temporaryDirectoryPath, name: "3", content: "3")
        let source4 = try createTemporaryFile(on: temporaryDirectoryPath, name: "4", content: "4")
        let framework1 = makeFramework(named: "f1", withSources: [source1, source2])
        let framework2 = makeFramework(named: "f2", withSources: [source3, source4])
        cache.add(targetNode: framework1)
        cache.add(targetNode: framework2)

        let contentHashes = try subject.contentHashes(for: graph)

        XCTAssertEqual(contentHashes[framework1], "f2156057d610c867d1eca703e1552124")
        XCTAssertEqual(contentHashes[framework2], "10e9b3ae9839c28fbf03bab0931df7a9")
    }

    func test_contentHashes_sourcesInDifferentOrder_hashIsConsistent() throws {
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)

        let temporaryDirectoryPath = try temporaryPath()
        let source1 = try createTemporaryFile(on: temporaryDirectoryPath, name: "1", content: "1")
        let source2 = try createTemporaryFile(on: temporaryDirectoryPath, name: "2", content: "2")
        let source3 = try createTemporaryFile(on: temporaryDirectoryPath, name: "3", content: "3")
        let source4 = try createTemporaryFile(on: temporaryDirectoryPath, name: "4", content: "4")
        let framework1 = makeFramework(named: "f1", withSources: [source2, source1])
        let framework2 = makeFramework(named: "f2", withSources: [source4, source3])
        cache.add(targetNode: framework1)
        cache.add(targetNode: framework2)

        let contentHashes = try subject.contentHashes(for: graph)

        XCTAssertEqual(contentHashes[framework1], "f2156057d610c867d1eca703e1552124")
        XCTAssertEqual(contentHashes[framework2], "10e9b3ae9839c28fbf03bab0931df7a9")
    }

    // MARK: - Private helpers

    private func createTemporaryFile(on temporaryDirectoryPath: AbsolutePath, name: String, content: String) throws -> Target.SourceFile {
        let filePath = temporaryDirectoryPath.appending(component: name)
        try FileHandler.shared.touch(filePath)
        try FileHandler.shared.write(content, path: filePath, atomically: true)
        return Target.SourceFile(path: filePath, compilerFlags: nil)
    }

    private func makeFramework(named: String,
                               platform: Platform = .iOS,
                               productName: String? = nil,
                               withSources sources: [Target.SourceFile]) -> TargetNode {
        TargetNode.test(
            project: .test(path: AbsolutePath("/test/\(named)")),
            target: .test(platform: platform,
                          product: .framework,
                          productName: productName,
                          sources: sources)
        )
    }
}
