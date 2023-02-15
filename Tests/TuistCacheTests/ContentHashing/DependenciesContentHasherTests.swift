import Foundation
import TSCBasic
import TuistCacheTesting
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistSupport
import XCTest
@testable import TuistCache
@testable import TuistSupportTesting

final class DependenciesContentHasherTests: TuistUnitTestCase {
    private var subject: DependenciesContentHasher!
    private var mockContentHasher: MockContentHasher!
    private var filePath1: AbsolutePath! = try! AbsolutePath(validating: "/file1")
    private var filePath2: AbsolutePath! = try! AbsolutePath(validating: "/file2")
    private var filePath3: AbsolutePath! = try! AbsolutePath(validating: "/file3")
    private var graphTarget: GraphTarget!
    private var hashedTargets: [GraphHashedTarget: String]!
    private var hashedPaths: [AbsolutePath: String]!

    override func setUp() {
        super.setUp()
        mockContentHasher = MockContentHasher()
        hashedTargets = [:]
        hashedPaths = [:]
        subject = DependenciesContentHasher(contentHasher: mockContentHasher)
    }

    override func tearDown() {
        subject = nil
        mockContentHasher = nil
        hashedTargets = nil
        hashedPaths = nil
        graphTarget = nil
        filePath1 = nil
        filePath2 = nil
        filePath3 = nil
        super.tearDown()
    }

    func test_hash_whenDependencyIsTarget_returnsTheRightHash() throws {
        // Given
        let dependency = TargetDependency.target(name: "foo")

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        hashedTargets[GraphHashedTarget(projectPath: graphTarget.path, targetName: "foo")] = "target-foo-hash"
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "target-foo-hash")
    }

    func test_hash_whenDependencyIsTarget_throwsWhenTheDependencyHasntBeenHashed() throws {
        // Given
        let dependency = TargetDependency.target(name: "foo")

        // When/Then
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let expectedError = DependenciesContentHasherError.missingTargetHash(
            sourceTargetName: graphTarget.target.name,
            dependencyProjectPath: graphTarget.path,
            dependencyTargetName: "foo"
        )
        XCTAssertThrowsSpecific(
            try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths),
            expectedError
        )
    }

    func test_hash_whenDependencyIsProject_returnsTheRightHash() throws {
        // Given
        let dependency = TargetDependency.project(target: "foo", path: filePath1)

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        hashedTargets[GraphHashedTarget(projectPath: filePath1, targetName: "foo")] = "project-file-hashed-foo-hash"
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "project-file-hashed-foo-hash")
    }

    func test_hash_whenDependencyIsProject_throwsAnErrorIfTheDependencyHashDoesntExist() throws {
        // Given
        let dependency = TargetDependency.project(target: "foo", path: filePath1)

        // When/Then
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let expectedError = DependenciesContentHasherError.missingProjectTargetHash(
            sourceProjectPath: graphTarget.path,
            sourceTargetName: graphTarget.target.name,
            dependencyProjectPath: filePath1,
            dependencyTargetName: "foo"
        )
        XCTAssertThrowsSpecific(
            try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths),
            expectedError
        )
    }

    func test_hash_whenDependencyIsFramework_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.framework(path: filePath1)
        mockContentHasher.stubHashForPath[filePath1] = "file-hashed"

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "file-hashed")
        XCTAssertEqual(mockContentHasher.hashPathCallCount, 1)
    }

    func test_hash_whenDependencyIsXCFramework_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.xcframework(path: filePath1)
        mockContentHasher.stubHashForPath[filePath1] = "file-hashed"

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "file-hashed")
        XCTAssertEqual(mockContentHasher.hashPathCallCount, 1)
    }

    func test_hash_whenDependencyIsLibrary_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.library(
            path: filePath1,
            publicHeaders: filePath2,
            swiftModuleMap: filePath3
        )
        mockContentHasher.stubHashForPath[filePath1] = "file1-hashed"
        mockContentHasher.stubHashForPath[filePath2] = "file2-hashed"
        mockContentHasher.stubHashForPath[filePath3] = "file3-hashed"

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "library-file1-hashed-file2-hashed-file3-hashed-hash")
        XCTAssertEqual(mockContentHasher.hashPathCallCount, 3)
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenDependencyIsLibrary_swiftModuleMapIsNil_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.library(
            path: filePath1,
            publicHeaders: filePath2,
            swiftModuleMap: nil
        )
        mockContentHasher.stubHashForPath[filePath1] = "file1-hashed"
        mockContentHasher.stubHashForPath[filePath2] = "file2-hashed"

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "library-file1-hashed-file2-hashed-hash")
        XCTAssertEqual(mockContentHasher.hashPathCallCount, 2)
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenDependencyIsPackage_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.package(product: "foo")

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "package-foo-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenDependencyIsOptionalSDK_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.sdk(name: "foo", status: .optional)

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "sdk-foo-optional-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenDependencyIsRequiredSDK_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.sdk(name: "foo", status: .required)

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "sdk-foo-required-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenDependencyIsXCTest_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.xctest

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "xctest-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }
}
