import Foundation
import MockableTest
import Path
import TuistCore
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class DependenciesContentHasherTests: TuistUnitTestCase {
    private var subject: DependenciesContentHasher!
    private var contentHasher: MockContentHashing!
    private var filePath1: AbsolutePath! = try! AbsolutePath(validating: "/file1")
    private var filePath2: AbsolutePath! = try! AbsolutePath(validating: "/file2")
    private var filePath3: AbsolutePath! = try! AbsolutePath(validating: "/file3")
    private var graphTarget: GraphTarget!
    private var hashedTargets: [GraphHashedTarget: String]!
    private var hashedPaths: [AbsolutePath: String]!

    override func setUp() {
        super.setUp()
        contentHasher = .init()
        hashedTargets = [:]
        hashedPaths = [:]
        subject = DependenciesContentHasher(contentHasher: contentHasher)

        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }
    }

    override func tearDown() {
        subject = nil
        contentHasher = nil
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
        hashedTargets[
            GraphHashedTarget(
                projectPath: graphTarget.path,
                targetName: "foo"
            )
        ] = "target-foo-hash"
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
        hashedTargets[
            GraphHashedTarget(
                projectPath: filePath1,
                targetName: "foo"
            )
        ] = "project-file-hashed-foo-hash"
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "project-file-hashed-foo-hash")
    }

    func test_hash_whenDependencyIsProjectWithACondition_returnsTheRightHash() throws {
        // Given
        let dependency = TargetDependency.project(target: "foo", path: filePath1, condition: .when([.ios]))

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        hashedTargets[
            GraphHashedTarget(
                projectPath: filePath1,
                targetName: "foo"
            )
        ] = "project-file-hashed-foo-hash"
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
        let dependency = TargetDependency.framework(path: filePath1, status: .required)
        given(contentHasher)
            .hash(path: .value(filePath1))
            .willReturn("file-hashed")

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "file-hashed")
        verify(contentHasher)
            .hash(path: .any)
            .called(1)
    }

    func test_hash_whenDependencyIsXCFramework_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.xcframework(path: filePath1, status: .required)
        given(contentHasher)
            .hash(path: .value(filePath1))
            .willReturn("file-hashed")

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "file-hashed")
        verify(contentHasher)
            .hash(path: .any)
            .called(1)
    }

    func test_hash_whenDependencyIsLibrary_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.library(
            path: filePath1,
            publicHeaders: filePath2,
            swiftModuleMap: filePath3
        )
        given(contentHasher)
            .hash(path: .value(filePath1))
            .willReturn("file1-hashed")
        given(contentHasher)
            .hash(path: .value(filePath2))
            .willReturn("file2-hashed")
        given(contentHasher)
            .hash(path: .value(filePath3))
            .willReturn("file3-hashed")

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "library-file1-hashed-file2-hashed-file3-hashed-hash")
        verify(contentHasher)
            .hash(path: .any)
            .called(3)
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
    }

    func test_hash_whenDependencyIsLibrary_swiftModuleMapIsNil_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.library(
            path: filePath1,
            publicHeaders: filePath2,
            swiftModuleMap: nil
        )
        given(contentHasher)
            .hash(path: .value(filePath1))
            .willReturn("file1-hashed")
        given(contentHasher)
            .hash(path: .value(filePath2))
            .willReturn("file2-hashed")

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "library-file1-hashed-file2-hashed-hash")
        verify(contentHasher)
            .hash(path: .any)
            .called(2)
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
    }

    func test_hash_whenDependencyIsPackage_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.package(product: "foo", type: .runtime)

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "package-foo-runtime-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
    }

    func test_hash_whenDependencyIsOptionalSDK_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.sdk(name: "foo", status: .optional)

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "sdk-foo-optional-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
    }

    func test_hash_whenDependencyIsRequiredSDK_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.sdk(name: "foo", status: .required)

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "sdk-foo-required-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
    }

    func test_hash_whenDependencyIsXCTest_callsContentHasherAsExpected() throws {
        // Given
        let dependency = TargetDependency.xctest

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "xctest-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
    }

    func test_hash_sorts_dependency_hashes() throws {
        // Given
        let dependencyFoo = TargetDependency.target(name: "foo")
        let dependencyBar = TargetDependency.target(name: "bar")

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependencyFoo, dependencyBar]))
        hashedTargets[
            GraphHashedTarget(
                projectPath: graphTarget.path,
                targetName: "foo"
            )
        ] = "target-foo-hash"
        hashedTargets[
            GraphHashedTarget(
                projectPath: graphTarget.path,
                targetName: "bar"
            )
        ] = "target-bar-hash"
        let hash = try subject.hash(graphTarget: graphTarget, hashedTargets: &hashedTargets, hashedPaths: &hashedPaths)

        // Then
        XCTAssertEqual(hash, "target-bar-hashtarget-foo-hash")
    }
}
