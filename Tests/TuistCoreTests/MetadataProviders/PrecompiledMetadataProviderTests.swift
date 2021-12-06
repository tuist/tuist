import Foundation
import TSCBasic
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistCore
@testable import TuistSupportTesting

final class PrecompiledMetadataProviderTests: TuistUnitTestCase {
    var subject: PrecompiledMetadataProvider!

    override func setUp() {
        super.setUp()
        subject = PrecompiledMetadataProvider()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_metadata_static() throws {
        // Given
        let binaryPath = fixturePath(path: RelativePath("libStaticLibrary.a"))

        // When
        let architectures = try subject.architectures(binaryPath: binaryPath)
        let linking = try subject.linking(binaryPath: binaryPath)
        let uuids = try subject.uuids(binaryPath: binaryPath)

        // Then
        XCTAssertEqual(architectures, [.x8664])
        XCTAssertEqual(linking, BinaryLinking.static)
        XCTAssertEqual(uuids, Set())
    }

    func test_metadata_carthage() throws {
        // Given
        let binaryPath = fixturePath(path: RelativePath("Carthage/RxBlocking.framework/RxBlocking"))

        // When
        let architectures = try subject.architectures(binaryPath: binaryPath)
        let linking = try subject.linking(binaryPath: binaryPath)
        let uuids = try subject.uuids(binaryPath: binaryPath)

        // Then
        XCTAssertEqual(architectures, [.i386, .x8664, .armv7, .arm64])
        XCTAssertEqual(linking, BinaryLinking.dynamic)
        XCTAssertEqual(
            uuids,
            Set([
                UUID(uuidString: "2510FE01-4D40-3956-BB71-857D3B2D9E73"),
                UUID(uuidString: "1C061BD7-371A-3039-8510-15CDF61531F6"),
                UUID(uuidString: "1208EC2E-0B7C-3B13-B5E1-6341E6AE6859"),
                UUID(uuidString: "773847A9-0D05-35AF-9865-94A9A670080B"),
            ])
        )
    }

    func test_metadata_framework() throws {
        // Given
        let binaryPath = fixturePath(path: RelativePath("xpm.framework/xpm"))

        // When
        let architectures = try subject.architectures(binaryPath: binaryPath)
        let linking = try subject.linking(binaryPath: binaryPath)
        let uuids = try subject.uuids(binaryPath: binaryPath)

        // Then
        XCTAssertEqual(architectures, [.x8664, .arm64])
        XCTAssertEqual(linking, BinaryLinking.dynamic)
        XCTAssertEqual(
            uuids,
            Set([
                UUID(uuidString: "FB17107A-86FA-3880-92AC-C9AA9E04BA98"),
                UUID(uuidString: "510FD121-B669-3524-A748-2DDF357A051C"),
            ])
        )
    }

    func test_metadata_xcframework() throws {
        // Given
        let binaryPath =
            fixturePath(path: RelativePath("MyFramework.xcframework/ios-x86_64-simulator/MyFramework.framework/MyFramework"))

        // When
        let architectures = try subject.architectures(binaryPath: binaryPath)
        let linking = try subject.linking(binaryPath: binaryPath)
        let uuids = try subject.uuids(binaryPath: binaryPath)

        // Then
        XCTAssertEqual(architectures, [.x8664])
        XCTAssertEqual(linking, BinaryLinking.dynamic)
        XCTAssertEqual(
            uuids,
            Set([
                UUID(uuidString: "725302D8-8353-312F-8BF4-564B24F7B3E8"),
            ])
        )
    }

    func test_metadata_static_xcframework() throws {
        // Given
        let binaryPath = fixturePath(path: RelativePath("MyStaticLibrary.xcframework/ios-arm64/libMyStaticLibrary.a"))

        // When
        let architectures = try subject.architectures(binaryPath: binaryPath)
        let linking = try subject.linking(binaryPath: binaryPath)
        let uuids = try subject.uuids(binaryPath: binaryPath)

        // Then
        XCTAssertEqual(architectures, [.arm64])
        XCTAssertEqual(linking, BinaryLinking.static)
        XCTAssertEqual(uuids, Set())
    }
}
