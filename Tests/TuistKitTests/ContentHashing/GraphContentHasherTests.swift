import Foundation
import XCTest
import TuistCoreTesting
import TuistCore
import Basic
@testable import TuistKit

final class GraphContentHasherTests: XCTestCase {
    private var sut: GraphContentHasher!
    
    override func setUp() {
        super.setUp()
        sut = GraphContentHasher()
     }

    override func tearDown() {
         sut = nil
         super.tearDown()
     }

    func test_contentHashes_emptyGraph() {
        let graph = Graph.test()
        let hashes = sut.contentHashes(for: graph)
        XCTAssertEqual(hashes, Dictionary())
    }

    func test_contentHashes_returnsOnlyFrameworks() {
        //Given
        let cache = GraphLoaderCache()
        let graph = Graph.test(cache: cache)
        let frameworkTarget = TargetNode.test(project: .test(path: AbsolutePath("/test/1")), target: .test(product: .framework))
        let secondFrameworkTarget = TargetNode.test(project: .test(path: AbsolutePath("/test/2")), target: .test(product: .framework))
        let appTarget = TargetNode.test(project: .test(path: AbsolutePath("/test/3")), target: .test(product: .app))
        let dynamicLibraryTarget = TargetNode.test(project: .test(path: AbsolutePath("/test/4")), target: .test(product: .dynamicLibrary))
        let staticFrameworkTarget = TargetNode.test(project: .test(path: AbsolutePath("/test/5")), target: .test(product: .staticFramework))
        cache.add(targetNode: frameworkTarget)
        cache.add(targetNode: secondFrameworkTarget)
        cache.add(targetNode: appTarget)
        cache.add(targetNode: dynamicLibraryTarget)
        cache.add(targetNode: staticFrameworkTarget)
        let expectedCachableTargets = [frameworkTarget, secondFrameworkTarget]
        
        // When
        let hashes = sut.contentHashes(for: graph)
        let hashedTargets: [TargetNode] = hashes.keys.sorted{ left, right -> Bool in
            left.project.path.pathString < right.project.path.pathString
        }
        
        // Then
        XCTAssertEqual(hashedTargets, expectedCachableTargets)
    }
}
