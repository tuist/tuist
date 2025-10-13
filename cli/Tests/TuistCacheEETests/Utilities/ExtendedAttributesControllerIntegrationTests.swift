import Foundation
import Path
import TuistSupport
import XCTest

@testable import TuistCacheEE
@testable import TuistCore
@testable import TuistTesting

final class ExtendedAttributesControllerIntegrationTests: TuistTestCase {
    var subject: ExtendedAttributesController!

    override func setUp() {
        super.setUp()
        subject = ExtendedAttributesController()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_setAttribute_and_getAttribute_set_and_return_attributes_when_file() throws {
        // Given
        let tmpDir = try temporaryPath()
        let filePath = tmpDir.appending(component: "file.txt")
        try FileHandler.shared.touch(filePath)

        // When
        try subject.setAttribute("foo", value: "bar", path: filePath)
        let got = try subject.getAttribute("foo", path: filePath)

        // Then
        XCTAssertEqual(got, "bar")
    }

    func test_setAttribute_and_getAttribute_set_and_return_attributes_when_directory() throws {
        // Given
        let tmpDir = try temporaryPath()

        // When
        try subject.setAttribute("foo", value: "bar", path: tmpDir)
        let got = try subject.getAttribute("foo", path: tmpDir)

        // Then
        XCTAssertEqual(got, "bar")
    }

    func test_getAttribute_returnsNil_when_theAttributeIsMissing_when_file() throws {
        // Given
        let tmpDir = try temporaryPath()
        let filePath = tmpDir.appending(component: "file.txt")
        try FileHandler.shared.touch(filePath)

        // When
        let got = try subject.getAttribute("foo", path: filePath)

        // Then
        XCTAssertNil(got)
    }

    func test_getAttribute_returnsNil_when_theAttributeIsMissing_when_directory() throws {
        // Given
        let tmpDir = try temporaryPath()

        // When
        let got = try subject.getAttribute("foo", path: tmpDir)

        // Then
        XCTAssertNil(got)
    }

    func test_removeAttribute_removesTheAttribute_when_file() throws {
        // Given
        let tmpDir = try temporaryPath()
        let filePath = tmpDir.appending(component: "file.txt")
        try FileHandler.shared.touch(filePath)

        // When
        try subject.setAttribute("foo", value: "bar", path: filePath)
        try subject.removeAttribute("foo", path: filePath)
        let got = try subject.getAttribute("foo", path: filePath)

        // Then
        XCTAssertNil(got)
    }

    func test_removeAttribute_removesTheAttribute_when_file_with_absent_attribute() throws {
        // Given
        let tmpDir = try temporaryPath()
        let filePath = tmpDir.appending(component: "file.txt")
        try FileHandler.shared.touch(filePath)

        // When
        try subject.removeAttribute("foo", path: filePath)
        let got = try subject.getAttribute("foo", path: filePath)

        // Then
        XCTAssertNil(got)
    }

    func test_removeAttribute_removesTheAttribute_when_directory() throws {
        // Given
        let tmpDir = try temporaryPath()

        // When
        try subject.setAttribute("foo", value: "bar", path: tmpDir)
        try subject.removeAttribute("foo", path: tmpDir)
        let got = try subject.getAttribute("foo", path: tmpDir)

        // Then
        XCTAssertNil(got)
    }

    func test_removeAttribute_removesTheAttribute_when_directory_with_absent_attribute() throws {
        // Given
        let tmpDir = try temporaryPath()

        // When
        try subject.removeAttribute("foo", path: tmpDir)
        let got = try subject.getAttribute("foo", path: tmpDir)

        // Then
        XCTAssertNil(got)
    }
}
