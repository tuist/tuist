import TSCBasic
import TuistGraph
import TuistSupport
import XCTest
@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class LibraryNodeLoaderErrorTests: TuistUnitTestCase {
    func test_type_when_libraryNotFound() {
        // Given
        let path = AbsolutePath("/libraries/libTuist.a")
        let subject = LibraryNodeLoaderError.libraryNotFound(path)

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_libraryNotFound() {
        // Given
        let path = AbsolutePath("/libraries/libTuist.a")
        let subject = LibraryNodeLoaderError.libraryNotFound(path)

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The library \(path.pathString) does not exist")
    }

    func test_type_when_publicHeadersNotFound() {
        // Given
        let path = AbsolutePath("/libraries/libTuist.a")
        let subject = LibraryNodeLoaderError.publicHeadersNotFound(path)

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_publicHeadersNotFound() {
        // Given
        let path = AbsolutePath("/libraries/libTuist.a")
        let subject = LibraryNodeLoaderError.publicHeadersNotFound(path)

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The public headers directory \(path.pathString) does not exist")
    }

    func test_type_when_swiftModuleMapNotFound() {
        // Given
        let path = AbsolutePath("/libraries/libTuist.a")
        let subject = LibraryNodeLoaderError.swiftModuleMapNotFound(path)

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_swiftModuleMapNotFound() {
        // Given
        let path = AbsolutePath("/libraries/libTuist.a")
        let subject = LibraryNodeLoaderError.swiftModuleMapNotFound(path)

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The Swift modulemap file \(path.pathString) does not exist")
    }
}

final class LibraryNodeLoaderTests: TuistUnitTestCase {
    var libraryMetadataProvider: MockLibraryMetadataProvider!
    var subject: LibraryNodeLoader!

    override func setUp() {
        libraryMetadataProvider = MockLibraryMetadataProvider()
        subject = LibraryNodeLoader(libraryMetadataProvider: libraryMetadataProvider)
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
        libraryMetadataProvider = nil
        subject = nil
    }

    func test_load_when_the_path_doesnt_exist() throws {
        // Given
        let path = try temporaryPath()
        let libraryPath = path.appending(component: "libTuist.a")
        let publicHeadersPath = path.appending(component: "headers")

        try FileHandler.shared.createFolder(publicHeadersPath)

        // Then
        XCTAssertThrowsSpecific(try subject.load(
            path: libraryPath,
            publicHeaders: publicHeadersPath,
            swiftModuleMap: nil
        ), LibraryNodeLoaderError.libraryNotFound(libraryPath))
    }

    func test_load_when_the_public_headers_directory_doesnt_exist() throws {
        // Given
        let path = try temporaryPath()
        let libraryPath = path.appending(component: "libTuist.a")
        let publicHeadersPath = path.appending(component: "headers")

        try FileHandler.shared.touch(libraryPath)

        // Then
        XCTAssertThrowsSpecific(try subject.load(
            path: libraryPath,
            publicHeaders: publicHeadersPath,
            swiftModuleMap: nil
        ), LibraryNodeLoaderError.publicHeadersNotFound(publicHeadersPath))
    }

    func test_load_when_the_swift_modulemap_doesnt_exist() throws {
        // Given
        let path = try temporaryPath()
        let libraryPath = path.appending(component: "libTuist.a")
        let publicHeadersPath = path.appending(component: "headers")
        let swiftModulemapPath = path.appending(component: "tuist.modulemap")
        try FileHandler.shared.createFolder(publicHeadersPath)
        try FileHandler.shared.touch(libraryPath)

        // Then
        XCTAssertThrowsSpecific(try subject.load(
            path: libraryPath,
            publicHeaders: publicHeadersPath,
            swiftModuleMap: swiftModulemapPath
        ), LibraryNodeLoaderError.swiftModuleMapNotFound(swiftModulemapPath))
    }

    func test_load_when_all_files_exist() throws {
        // Given
        let path = try temporaryPath()
        let libraryPath = path.appending(component: "libTuist.a")
        let publicHeadersPath = path.appending(component: "headers")
        let swiftModulemapPath = path.appending(component: "tuist.modulemap")
        let architectures: [BinaryArchitecture] = [.armv7, .armv7s]
        let linking: BinaryLinking = .dynamic

        try FileHandler.shared.createFolder(publicHeadersPath)
        try FileHandler.shared.touch(libraryPath)
        try FileHandler.shared.touch(swiftModulemapPath)

        libraryMetadataProvider.architecturesStub = { path in
            XCTAssertEqual(path, libraryPath)
            return architectures
        }
        libraryMetadataProvider.linkingStub = { path in
            XCTAssertEqual(path, libraryPath)
            return linking
        }

        // When
        let got = try subject.load(
            path: libraryPath,
            publicHeaders: publicHeadersPath,
            swiftModuleMap: swiftModulemapPath
        )

        // Then
        XCTAssertEqual(got, LibraryNode(
            path: libraryPath,
            publicHeaders: publicHeadersPath,
            architectures: architectures,
            linking: linking,
            swiftModuleMap: swiftModulemapPath
        ))
    }
}
