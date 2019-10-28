import Basic
import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistGenerator

final class BinaryArchitectureTests: TuistTestCase {
    func test_rawValue() {
        XCTAssertEqual(BinaryArchitecture.x8664.rawValue, "x86_64")
        XCTAssertEqual(BinaryArchitecture.i386.rawValue, "i386")
        XCTAssertEqual(BinaryArchitecture.armv7.rawValue, "armv7")
        XCTAssertEqual(BinaryArchitecture.armv7s.rawValue, "armv7s")
    }
}

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

    func test_architectures() throws {
        // Given
        system.succeedCommand("/usr/bin/lipo", "-info", "/test.a", output: "Non-fat file: path is architecture: x86_64")

        // When
        let got = try subject.architectures(binaryPath: AbsolutePath("/test.a"))

        // Then
        XCTAssertEqual(got.first, .x8664)
    }

    func test_linking() throws {
        // Given
        system.succeedCommand("/usr/bin/file", "/test.a", output: "whatever dynamically linked")

        // When
        let got = try subject.linking(binaryPath: AbsolutePath("/test.a"))

        // Then
        XCTAssertEqual(got, .dynamic)
    }
}
