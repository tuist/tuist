import Foundation
import TSCBasic
import TuistSupport

import XCTest

@testable import TuistCore
@testable import TuistSupportTesting

final class PrecompiledMetadataProviderIntegrationTests: TuistTestCase {
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
        let frameworkPath = try temporaryFixture("xpm.framework")

        // When
        let got = try subject.architectures(binaryPath: FrameworkMetadataProvider().loadMetadata(at: frameworkPath).binaryPath)

        // Then
        XCTAssertEqual(got.map(\.rawValue).sorted(), ["arm64", "x86_64"])
    }

    func test_uuids() throws {
        // Given
        let frameworkPath = try temporaryFixture("xpm.framework")

        // When
        let got = try subject.uuids(binaryPath: FrameworkMetadataProvider().loadMetadata(at: frameworkPath).binaryPath)

        // Then
        let expected = Set([
            UUID(uuidString: "FB17107A-86FA-3880-92AC-C9AA9E04BA98"),
            UUID(uuidString: "510FD121-B669-3524-A748-2DDF357A051C"),
        ])
        XCTAssertEqual(got, expected)
    }
}
