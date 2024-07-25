import Foundation
import MockableTest
import Path
import TuistCore
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class CoreDataModelsContentHasherTests: TuistUnitTestCase {
    private var subject: CoreDataModelsContentHasher!
    private var coreDataModel: CoreDataModel!
    private var contentHasher: MockContentHashing!
    private let defaultValuesHash =
        "05c9d517e2cf12b45786787dae929a23" // Expected hash for the CoreDataModel created with the buildCoreDataModel function
    // using default values

    override func setUp() {
        super.setUp()
        contentHasher = .init()
        subject = CoreDataModelsContentHasher(contentHasher: contentHasher)
        do {
            _ = try TemporaryDirectory(removeTreeOnDeinit: true)
        } catch {
            XCTFail("Error while creating temporary directory")
        }
        given(contentHasher)
            .hash(Parameter<[String]>.any)
            .willProduce { $0.joined(separator: ";") }
    }

    override func tearDown() {
        subject = nil
        coreDataModel = nil
        contentHasher = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_hash_returnsSameValue() throws {
        // Given
        coreDataModel = try buildCoreDataModel(versions: ["v1", "v2"], currentVersion: "currentV1")
        given(contentHasher)
            .hash(path: .any)
            .willProduce { $0.basename }

        // When
        let hash = try subject.hash(coreDataModels: [coreDataModel])

        // Then
        XCTAssertEqual(hash, "fixed-hash;currentV1;v1;v2")
    }

    func test_hash_fileContentChangesHash() throws {
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
        let hash = try subject.hash(coreDataModels: [coreDataModel])

        // Then
        XCTAssertNotEqual(hash, defaultValuesHash)
    }

    func test_hash_currentVersionChangesHash() throws {
        // Given
        coreDataModel = try buildCoreDataModel(currentVersion: "2")
        given(contentHasher)
            .hash(path: .any)
            .willProduce { $0.basename }

        // When
        let hash = try subject.hash(coreDataModels: [coreDataModel])

        XCTAssertNotEqual(hash, defaultValuesHash)
    }

    func test_hash_versionsChangeHash() throws {
        // Given
        coreDataModel = try buildCoreDataModel(versions: ["1", "2", "3"])
        given(contentHasher)
            .hash(path: .any)
            .willProduce { $0.basename }

        // When
        let hash = try subject.hash(coreDataModels: [coreDataModel])

        // Then
        XCTAssertNotEqual(hash, defaultValuesHash)
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
