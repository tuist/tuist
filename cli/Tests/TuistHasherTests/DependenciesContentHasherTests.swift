import Foundation
import Mockable
import Path
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import Testing

@testable import TuistHasher

struct DependenciesContentHasherTests {
    private let subject: DependenciesContentHasher
    private let contentHasher: MockContentHashing
    private let filePath1: AbsolutePath = try! AbsolutePath(validating: "/file1")
    private let filePath2: AbsolutePath = try! AbsolutePath(validating: "/file2")
    private let filePath3: AbsolutePath = try! AbsolutePath(validating: "/file3")
    init() {
        contentHasher = .init()
        subject = DependenciesContentHasher(contentHasher: contentHasher)
        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }
    }

    @Test
    func test_hash_whenDependencyIsTarget_returnsTheRightHash() async throws {
        // Given
        let dependency = TargetDependency.target(name: "foo")

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hashedTargets: [GraphHashedTarget: String] = [
            GraphHashedTarget(projectPath: graphTarget.path, targetName: "foo"): "target-foo-hash",
        ]
        let hash = try await subject.hash(graphTarget: graphTarget, hashedTargets: hashedTargets, hashedPaths: [:]).hash

        // Then
        #expect(hash == "target-foo-hash-hash")
    }

    @Test
    func test_hash_whenDependencyIsTarget_throwsWhenTheDependencyHasntBeenHashed() async throws {
        // Given
        let dependency = TargetDependency.target(name: "foo")

        // When/Then
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let expectedError = DependenciesContentHasherError.missingTargetHash(
            sourceTargetName: graphTarget.target.name,
            dependencyProjectPath: graphTarget.path,
            dependencyTargetName: "foo"
        )
        await #expect(throws: expectedError) { try await subject.hash(graphTarget: graphTarget, hashedTargets: [:], hashedPaths: [:]).hash }
    }

    @Test
    func test_hash_whenDependencyIsProject_returnsTheRightHash() async throws {
        // Given
        let dependency = TargetDependency.project(target: "foo", path: filePath1)

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hashedTargets: [GraphHashedTarget: String] = [
            GraphHashedTarget(projectPath: filePath1, targetName: "foo"): "project-file-hashed-foo-hash",
        ]
        let hash = try await subject.hash(graphTarget: graphTarget, hashedTargets: hashedTargets, hashedPaths: [:]).hash

        // Then
        #expect(hash == "project-file-hashed-foo-hash-hash")
    }

    @Test
    func test_hash_whenDependencyIsProjectWithACondition_returnsTheRightHash() async throws {
        // Given
        let dependency = TargetDependency.project(target: "foo", path: filePath1, condition: .when([.ios]))

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hashedTargets: [GraphHashedTarget: String] = [
            GraphHashedTarget(projectPath: filePath1, targetName: "foo"): "project-file-hashed-foo-hash",
        ]
        let hash = try await subject.hash(graphTarget: graphTarget, hashedTargets: hashedTargets, hashedPaths: [:]).hash

        // Then
        #expect(hash == "project-file-hashed-foo-hash-hash")
    }

    @Test
    func test_hash_whenDependencyIsProject_throwsAnErrorIfTheDependencyHashDoesntExist() async throws {
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
        await #expect(throws: expectedError) { try await subject.hash(graphTarget: graphTarget, hashedTargets: [:], hashedPaths: [:]).hash }
    }

    @Test
    func test_hash_whenDependencyIsFramework_callsContentHasherAsExpected() async throws {
        // Given
        let dependency = TargetDependency.framework(path: filePath1, status: .required)
        given(contentHasher)
            .hash(path: .value(filePath1))
            .willReturn("file-hashed")

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try await subject.hash(graphTarget: graphTarget, hashedTargets: [:], hashedPaths: [:]).hash

        // Then
        #expect(hash == "file-hashed-hash")
        verify(contentHasher)
            .hash(path: .any)
            .called(1)
    }

    @Test
    func test_hash_whenDependencyIsXCFramework_callsContentHasherAsExpected() async throws {
        // Given
        let dependency = TargetDependency.xcframework(path: filePath1, expectedSignature: nil, status: .required)
        given(contentHasher)
            .hash(path: .value(filePath1))
            .willReturn("file-hashed")

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try await subject.hash(graphTarget: graphTarget, hashedTargets: [:], hashedPaths: [:]).hash

        // Then
        #expect(hash == "file-hashed-hash")
        verify(contentHasher)
            .hash(path: .any)
            .called(1)
    }

    @Test
    func test_hash_whenDependencyIsLibrary_callsContentHasherAsExpected() async throws {
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
        let hash = try await subject.hash(graphTarget: graphTarget, hashedTargets: [:], hashedPaths: [:]).hash

        // Then
        #expect(hash == "library-file1-hashed-file2-hashed-file3-hashed-hash-hash")
        verify(contentHasher)
            .hash(path: .any)
            .called(3)
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(2)
    }

    @Test
    func test_hash_whenDependencyIsLibrary_swiftModuleMapIsNil_callsContentHasherAsExpected() async throws {
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
        let hash = try await subject.hash(graphTarget: graphTarget, hashedTargets: [:], hashedPaths: [:]).hash

        // Then
        #expect(hash == "library-file1-hashed-file2-hashed-hash-hash")
        verify(contentHasher)
            .hash(path: .any)
            .called(2)
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(2)
    }

    @Test
    func test_hash_whenDependencyIsPackage_callsContentHasherAsExpected() async throws {
        // Given
        let dependency = TargetDependency.package(product: "foo", type: .runtime)

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try await subject.hash(graphTarget: graphTarget, hashedTargets: [:], hashedPaths: [:]).hash

        // Then
        #expect(hash == "package-foo-runtime-hash-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(2)
    }

    @Test
    func test_hash_whenDependencyIsOptionalSDK_callsContentHasherAsExpected() async throws {
        // Given
        let dependency = TargetDependency.sdk(name: "foo", status: .optional)

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try await subject.hash(graphTarget: graphTarget, hashedTargets: [:], hashedPaths: [:]).hash

        // Then
        #expect(hash == "sdk-foo-optional-hash-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(2)
    }

    @Test
    func test_hash_whenDependencyIsRequiredSDK_callsContentHasherAsExpected() async throws {
        // Given
        let dependency = TargetDependency.sdk(name: "foo", status: .required)

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try await subject.hash(graphTarget: graphTarget, hashedTargets: [:], hashedPaths: [:]).hash

        // Then
        #expect(hash == "sdk-foo-required-hash-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(2)
    }

    @Test
    func test_hash_whenDependencyIsXCTest_callsContentHasherAsExpected() async throws {
        // Given
        let dependency = TargetDependency.xctest

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependency]))
        let hash = try await subject.hash(graphTarget: graphTarget, hashedTargets: [:], hashedPaths: [:]).hash

        // Then
        #expect(hash == "xctest-hash-hash")
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(2)
    }

    @Test
    func test_hash_sorts_dependency_hashes() async throws {
        // Given
        let dependencyFoo = TargetDependency.target(name: "foo")
        let dependencyBar = TargetDependency.target(name: "bar")

        // When
        let graphTarget = GraphTarget.test(target: Target.test(dependencies: [dependencyFoo, dependencyBar]))
        let hashedTargets: [GraphHashedTarget: String] = [
            GraphHashedTarget(projectPath: graphTarget.path, targetName: "foo"): "target-foo-hash",
            GraphHashedTarget(projectPath: graphTarget.path, targetName: "bar"): "target-bar-hash",
        ]
        let hash = try await subject.hash(graphTarget: graphTarget, hashedTargets: hashedTargets, hashedPaths: [:]).hash

        // Then
        #expect(hash == "target-bar-hashtarget-foo-hash-hash")
    }
}
