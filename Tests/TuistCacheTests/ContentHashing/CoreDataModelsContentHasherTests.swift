import Basic
import Foundation
import TuistCore
import TuistCoreTesting
import XCTest
import TuistSupport
import TuistCacheTesting
@testable import TuistCache


final class CoreDataModelsContentHasherTests: XCTestCase {
    private var sut: CoreDataModelsContentHasher!
    private var coreDataModel: CoreDataModel!
    private var temporaryDirectory: TemporaryDirectory!
    private var mockContentHasher: MockContentHashing!
    private let defaultValuesHash = "05c9d517e2cf12b45786787dae929a23" // Expected hash for the CoreDataModel created with the buildCoreDataModel function using default values
    override func setUp() {
        super.setUp()
        mockContentHasher = MockContentHashing()
        sut = CoreDataModelsContentHasher(contentHasher: mockContentHasher)
        do {
            temporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        } catch {
            XCTFail("Error while creating temporary directory")
        }
    }

    override func tearDown() {
        sut = nil
        coreDataModel = nil
        temporaryDirectory = nil
        mockContentHasher = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_hash_returnsSameValue() throws {
        coreDataModel = try buildCoreDataModel()
        mockContentHasher.hashStringsStub = "fixed"

        let hash = try sut.hash(coreDataModels: [coreDataModel])

        XCTAssertEqual(hash, "fixed")
    }

    func test_hash_fileContentChangesHash() throws {
        let name = "CoreDataModel"
        coreDataModel = try buildCoreDataModel()
        let fakePath = buildFakePath(from: name)
        mockContentHasher.stubHashForPath[fakePath] = "different-hash"

        let hash = try sut.hash(coreDataModels: [coreDataModel])

        XCTAssertNotEqual(hash, defaultValuesHash)
    }

    func test_hash_currentVersionChangesHash() throws {
        coreDataModel = try buildCoreDataModel(currentVersion: "2")

        let hash = try sut.hash(coreDataModels: [coreDataModel])

        XCTAssertNotEqual(hash, defaultValuesHash)
    }

    func test_hash_versionsChangeHash() throws {
        coreDataModel = try buildCoreDataModel(versions: ["1", "2", "3"])

        let hash = try sut.hash(coreDataModels: [coreDataModel])

        XCTAssertNotEqual(hash, defaultValuesHash)
    }

    // MARK: - Private

    private func buildFakePath(from name: String) -> AbsolutePath {
        return AbsolutePath("/\(name)+path")
    }

    private func buildCoreDataModel(name: String = "CoreDataModel",
                                    versions: [String] = ["1", "2"],
                                    currentVersion: String = "1") throws -> CoreDataModel {
        let fakePath = buildFakePath(from: name)
        mockContentHasher.stubHashForPath[fakePath] = "fixed-hash"
        let versionsAbsolutePaths = versions.map { AbsolutePath("/\($0)") }
        return CoreDataModel(path: fakePath,
                             versions: versionsAbsolutePaths,
                             currentVersion: currentVersion)
    }
}
