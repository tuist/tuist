import Foundation
import TSCBasic
import TuistCacheTesting
import TuistCore
import TuistCoreTesting
import TuistSupport
import XCTest
@testable import TuistCache
@testable import TuistSupportTesting

final class DependenciesContentHasherTests: TuistUnitTestCase {
    private var subject: DependenciesContentHasher!
    private var mockContentHasher: MockContentHashing!
    private let filePath1 = AbsolutePath("/file1")
    private let filePath2 = AbsolutePath("/file2")
    private let filePath3 = AbsolutePath("/file3")

    override func setUp() {
        super.setUp()
        mockContentHasher = MockContentHashing()
        subject = DependenciesContentHasher(contentHasher: mockContentHasher)
    }

    override func tearDown() {
        subject = nil
        mockContentHasher = nil
        super.tearDown()
    }

    func test_hash_whenDependencyIsTarget_callsContentHasherAsExpected() throws {
        // Given
        let dependency = Dependency.target(name: "foo")

        // When
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "target-foo-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenDependencyIsProject_callsContentHasherAsExpected() throws {
        // Given
        let dependency = Dependency.project(target: "foo", path: filePath1)

        // When
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "project-;foo;/file1")
        XCTAssertEqual(mockContentHasher.hashStringsCallCount, 1)
    }

    func test_hash_whenDependencyIsFramework_callsContentHasherAsExpected() throws {
        // Given
        let dependency = Dependency.framework(path: filePath1)

        // When
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "framework-/file1-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenDependencyIsXCFramework_callsContentHasherAsExpected() throws {
        // Given
        let dependency = Dependency.xcFramework(path: filePath1)

        // When
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "xcframework-/file1-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenDependencyIsLibrary_callsContentHasherAsExpected() throws {
        // Given
        let dependency = Dependency.library(path: filePath1,
                                            publicHeaders: filePath2,
                                            swiftModuleMap: filePath3)

        // When
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "library;/file1;/file2;/file3")
        XCTAssertEqual(mockContentHasher.hashStringsCallCount, 1)
    }

    func test_hash_whenDependencyIsPackage_callsContentHasherAsExpected() throws {
        // Given
        let dependency = Dependency.package(product: "foo")

        // When
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "package-foo-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenDependencyIsOptionalSDK_callsContentHasherAsExpected() throws {
        // Given
        let dependency = Dependency.sdk(name: "foo", status: .optional)

        // When
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "sdk-foo-optional-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenDependencyIsRequiredSDK_callsContentHasherAsExpected() throws {
        // Given
        let dependency = Dependency.sdk(name: "foo", status: .required)

        // When
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "sdk-foo-required-hash")
        XCTAssertEqual(mockContentHasher.hashStringCallCount, 1)
    }

    func test_hash_whenDependencyIsCocoapods_callsContentHasherAsExpected() throws {
        // Given
        let dependency = Dependency.cocoapods(path: filePath1)

        // When
        let hash = try subject.hash(dependencies: [dependency])

        // Then
        XCTAssertEqual(hash, "cocoapods;/file1")
        XCTAssertEqual(mockContentHasher.hashStringsCallCount, 1)
    }
}
