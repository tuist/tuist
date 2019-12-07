import Basic
import Foundation
import TuistSupport
import XCTest
import TuistCore
import TuistCoreTesting

@testable import TuistKit
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
        
        let temporaryDirectoryPath = try self.temporaryPath()
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
        
        let temporaryDirectoryPath = try self.temporaryPath()
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
    
    func test_contentHashes_hashIsConsistent() throws {
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)
        
        let temporaryDirectoryPath = try self.temporaryPath()
        let source1 = try createTemporaryFile(on: temporaryDirectoryPath, name: "1", content: "1")
        let source2 = try createTemporaryFile(on: temporaryDirectoryPath, name: "2", content: "2")
        let source3 = try createTemporaryFile(on: temporaryDirectoryPath, name: "3", content: "3")
        let source4 = try createTemporaryFile(on: temporaryDirectoryPath, name: "4", content: "4")
        let framework1 = makeFramework(named: "f1", withSources: [source1, source2])
        let framework2 = makeFramework(named: "f2", withSources: [source3, source4])
        cache.add(targetNode: framework1)
        cache.add(targetNode: framework2)
        
        let contentHashes = try subject.contentHashes(for: graph)
        
        XCTAssertEqual(contentHashes[framework1], "302cbafc0dfbc97f30d576a6f394dad3")
        XCTAssertEqual(contentHashes[framework2], "284914d9fc3eba381602a8adc626fbfd")
    }
    
    // MARK: - Private helpers
    
    private func createTemporaryFile(on temporaryDirectoryPath: AbsolutePath, name: String, content: String) throws -> Target.SourceFile {
        let filePath = temporaryDirectoryPath.appending(component: name)
        try FileHandler.shared.touch(filePath)
        try FileHandler.shared.write(content, path: filePath, atomically: true)
        return Target.SourceFile(path: filePath, compilerFlags: nil)
    }
    
    private func makeFramework(named: String, withSources sources: [Target.SourceFile]) -> TargetNode {
        return TargetNode.test(project: .test(path: AbsolutePath("/test/\(named)")), target: .test(product: .framework, sources: sources))
    }
}
