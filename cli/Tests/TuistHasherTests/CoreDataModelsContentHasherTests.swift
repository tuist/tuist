import Foundation
import Mockable
import Path
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import Testing

@testable import TuistHasher

struct CoreDataModelsContentHasherTests {
    private let subject: CoreDataModelsContentHasher
    private let coreDataModel: CoreDataModel
    private let contentHasher: MockContentHashing
    private let defaultValuesHash =
        "05c9d517e2cf12b45786787dae929a23" // Expected hash for the CoreDataModel created with the buildCoreDataModel function
    // using default values

    init() {
        contentHasher = .init()
        subject = CoreDataModelsContentHasher(contentHasher: contentHasher)
        do {
            _ = try TemporaryDirectory(removeTreeOnDeinit: true)
        } catch {
            Issue.record("Error while creating temporary directory")
        }
        given(contentHasher)
            .hash(Parameter<[String]>.any)
            .willProduce { $0.joined(separator: ";") }
    }


    // MARK: - Tests

    @Test
    func test_hash_returnsSameValue() async throws {
        // Given
        coreDataModel = try buildCoreDataModel(versions: ["v1", "v2"], currentVersion: "currentV1")
        given(contentHasher)
            .hash(path: .any)
            .willProduce { $0.basename }

        // When
        let hash = try await subject.hash(coreDataModels: [coreDataModel])

        // Then
        #expect(hash == "fixed-hash;currentV1;v1;v2")
    }

    @Test
    func test_hash_fileContentChangesHash() async throws {
        // Given
        let name = "CoreDataModel"
        coreDataModel = try buildCoreDataModel()
        let fakePath = buildFakePath(from: name)
        given(contentHasher)
            .hash(path: .any)
            .willProduce { $0.basename }
        given(contentHasher)
            .hash(path: .value(fakePath))
            .willReturn("different-hash")

        // When
        let hash = try await subject.hash(coreDataModels: [coreDataModel])

        // Then
        #expect(hash != defaultValuesHash)
    }

    @Test
    func test_hash_currentVersionChangesHash() async throws {
        // Given
        coreDataModel = try buildCoreDataModel(currentVersion: "2")
        given(contentHasher)
            .hash(path: .any)
            .willProduce { $0.basename }

        // When
        let hash = try await subject.hash(coreDataModels: [coreDataModel])

        #expect(hash != defaultValuesHash)
    }

    @Test
    func test_hash_versionsChangeHash() async throws {
        // Given
        coreDataModel = try buildCoreDataModel(versions: ["1", "2", "3"])
        given(contentHasher)
            .hash(path: .any)
            .willProduce { $0.basename }

        // When
        let hash = try await subject.hash(coreDataModels: [coreDataModel])

        // Then
        #expect(hash != defaultValuesHash)
    }

    @Test
    func test_hash_isDeterministicRegardlessOfInputOrder() async throws {
        // Given
        let modelA = CoreDataModel(
            path: try AbsolutePath(validating: "/AlphaModel+path"),
            versions: [try AbsolutePath(validating: "/v1")],
            currentVersion: "v1"
        )
        let modelB = CoreDataModel(
            path: try AbsolutePath(validating: "/BetaModel+path"),
            versions: [try AbsolutePath(validating: "/v1")],
            currentVersion: "v1"
        )
        given(contentHasher)
            .hash(path: .any)
            .willProduce { $0.basename }

        // When
        let hashAB = try await subject.hash(coreDataModels: [modelA, modelB])
        let hashBA = try await subject.hash(coreDataModels: [modelB, modelA])

        // Then
        #expect(hashAB == hashBA)
    }

    // MARK: - Private

    private func buildFakePath(from name: String) -> AbsolutePath {
        try! AbsolutePath(validating: "/\(name)+path")
    }

    private func buildCoreDataModel(
        name: String = "CoreDataModel",
        versions: [String] = ["1", "2"],
        currentVersion: String = "1"
    ) throws -> CoreDataModel {
        let fakePath = buildFakePath(from: name)

        given(contentHasher)
            .hash(path: .value(fakePath))
            .willReturn("fixed-hash")
        let versionsAbsolutePaths = try versions.map { try AbsolutePath(validating: "/\($0)") }
        return CoreDataModel(
            path: fakePath,
            versions: versionsAbsolutePaths,
            currentVersion: currentVersion
        )
    }
}
