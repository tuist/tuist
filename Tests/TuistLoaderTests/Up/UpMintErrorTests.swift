import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class UpMintErrorTests: TuistUnitTestCase {
    func test_type_when_mintFileNotFound() throws {
        // Given
        let upHomebrew = MockUp()
        let subject = UpMint(linkPackagesGlobally: false, upHomebrew: upHomebrew)
        let temporaryPath = try self.temporaryPath()

        upHomebrew.isMetStub = { _ in true }

        // Then
        XCTAssertThrowsSpecific(try subject.isMet(projectPath: temporaryPath), UpMintError.mintfileNotFound(temporaryPath))
    }

    func test_description_when_mintFileDescription() throws {
        // Given
        let mintfile = try temporaryPath().appending(component: "Mintfile")
        let error = UpMintError.mintfileNotFound(mintfile)

        // When
        let got = error.description

        // Then
        XCTAssertEqual(got, "Mintfile not found at path \(mintfile.pathString)")
    }
}
