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
    private let filePath1 = AbsolutePath("/file1")
    private let filePath2 = AbsolutePath("/file2")
    private let filePath3 = AbsolutePath("/file3")

    override func setUp() {
        super.setUp()
        mockContentHasher = MockContentHasher()
        subject = DependenciesContentHasher(contentHasher: mockContentHasher)
    }

    override func tearDown() {
        subject = nil
        mockContentHasher = nil
        super.tearDown()
    }

    func test_hash_whenDependencyIsTarget_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.target(name: "foo")

        // When
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "target-foo-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenDependencyIsProject_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.project(target: "foo", path: filePath1)
        mockContentHasher.stubHashForPath[filePath1] = "file-hashed"

        // When
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "project-file-hashed-foo-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
        XCTAssertEqual(mockContentHasher.hashPathCallCount, 1)
    }

    func test_hash_whenDependencyIsFramework_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.framework(path: filePath1)
        mockContentHasher.stubHashForPath[filePath1] = "file-hashed"

        // When
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "file-hashed")
        XCTAssertEqual(mockContentHasher.hashPathCallCount, 1)
    }

    func test_hash_whenDependencyIsXCFramework_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.xcFramework(path: filePath1)
        mockContentHasher.stubHashForPath[filePath1] = "file-hashed"

        // When
        let hash = try subject.hash(dependencies: [dependency])

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
        let hash = try subject.hash(dependencies: [dependency])

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
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "library-file1-hashed-file2-hashed-hash")
        XCTAssertEqual(mockContentHasher.hashPathCallCount, 2)
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenDependencyIsPackage_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.package(product: "foo")

        // When
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "package-foo-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenDependencyIsOptionalSDK_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.sdk(name: "foo", status: .optional)

        // When
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "sdk-foo-optional-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenDependencyIsRequiredSDK_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.sdk(name: "foo", status: .required)

        // When
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "sdk-foo-required-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenDependencyIsCocoapods_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.cocoapods(path: filePath1)
        mockContentHasher.stubHashForPath[filePath1] = "file1-hashed"

        // When
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "cocoapods-file1-hashed-hash")
        XCTAssertEqual(mockContentHasher.hashPathCallCount, 1)
    }

    func test_hash_whenDependencyIsXCTest_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.xctest

        // When
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "xctest-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }
}
