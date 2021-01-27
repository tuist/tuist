import TSCBasic
import TuistGraph
import TuistSupport
import XCTest
@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class LibraryDependencyLoaderErrorTests: TuistUnitTestCase {
    func test_type_when_libraryNotFound() {
        // Given
        let path = AbsolutePath("/libraries/libTuist.a")
        let subject = LibraryDependencyLoaderError.libraryNotFound(path)

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_libraryNotFound() {
        // Given
        let path = AbsolutePath("/libraries/libTuist.a")
        let subject = LibraryDependencyLoaderError.libraryNotFound(path)

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The library \(path.pathString) does not exist.")
    }

    func test_type_when_publicHeadersNotFound() {
        // Given
        let path = AbsolutePath("/libraries/libTuist.a")
        let subject = LibraryDependencyLoaderError.publicHeadersNotFound(path)

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_publicHeadersNotFound() {
        // Given
        let path = AbsolutePath("/libraries/libTuist.a")
        let subject = LibraryDependencyLoaderError.publicHeadersNotFound(path)

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The public headers directory \(path.pathString) does not exist.")
    }

    func test_type_when_swiftModuleMapNotFound() {
        // Given
        let path = AbsolutePath("/libraries/libTuist.a")
        let subject = LibraryDependencyLoaderError.swiftModuleMapNotFound(path)

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_swiftModuleMapNotFound() {
        // Given
        let path = AbsolutePath("/libraries/libTuist.a")
        let subject = LibraryDependencyLoaderError.swiftModuleMapNotFound(path)

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The Swift modulemap file \(path.pathString) does not exist.")
    }
}

final class LibraryDependencyLoaderTests: TuistUnitTestCase {
    var libraryMetadataProvider: MockLibraryMetadataProvider!
    var subject: LibraryDependencyLoader!

    override func setUp() {
        libraryMetadataProvider = MockLibraryMetadataProvider()
        subject = LibraryDependencyLoader(libraryMetadataProvider: libraryMetadataProvider)
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
        XCTAssertThrowsSpecific(try subject.load(path: libraryPath,
                                                 publicHeaders: publicHeadersPath,
                                                 swiftModuleMap: nil), LibraryDependencyLoaderError.libraryNotFound(libraryPath))
    }

    func test_load_when_the_public_headers_directory_doesnt_exist() throws {
        // Given
        let path = try temporaryPath()
        let libraryPath = path.appending(component: "libTuist.a")
        let publicHeadersPath = path.appending(component: "headers")

        try FileHandler.shared.touch(libraryPath)

        // Then
        XCTAssertThrowsSpecific(try subject.load(path: libraryPath,
                                                 publicHeaders: publicHeadersPath,
                                                 swiftModuleMap: nil), LibraryDependencyLoaderError.publicHeadersNotFound(publicHeadersPath))
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
        XCTAssertThrowsSpecific(try subject.load(path: libraryPath,
                                                 publicHeaders: publicHeadersPath,
                                                 swiftModuleMap: swiftModulemapPath), LibraryDependencyLoaderError.swiftModuleMapNotFound(swiftModulemapPath))
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
        let got = try subject.load(path: libraryPath,
                                   publicHeaders: publicHeadersPath,
                                   swiftModuleMap: swiftModulemapPath)

        // Then
        XCTAssertEqual(got, .library(path: libraryPath,
                                     publicHeaders: publicHeadersPath,
                                     linking: linking,
                                     architectures: architectures,
                                     swiftModuleMap: swiftModulemapPath))
    }
}
