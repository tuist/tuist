import FileSystemTesting
import Foundation
import Path
import Testing
import TuistSupport

@testable import TuistCacheEE
@testable import TuistCore
@testable import TuistTesting

struct ExtendedAttributesControllerIntegrationTests {
    let subject: ExtendedAttributesController
    init() {
        subject = ExtendedAttributesController()
    }

    @Test(.inTemporaryDirectory)
    func setAttribute_and_getAttribute_set_and_return_attributes_when_file() throws {
        // Given
        let tmpDir = try #require(FileSystem.temporaryTestDirectory)
        let filePath = tmpDir.appending(component: "file.txt")
        try FileHandler.shared.touch(filePath)

        // When
        try subject.setAttribute("foo", value: "bar", path: filePath)
        let got = try subject.getAttribute("foo", path: filePath)

        // Then
        #expect(got == "bar")
    }

    @Test(.inTemporaryDirectory)
    func setAttribute_and_getAttribute_set_and_return_attributes_when_directory() throws {
        // Given
        let tmpDir = try #require(FileSystem.temporaryTestDirectory)

        // When
        try subject.setAttribute("foo", value: "bar", path: tmpDir)
        let got = try subject.getAttribute("foo", path: tmpDir)

        // Then
        #expect(got == "bar")
    }

    @Test(.inTemporaryDirectory)
    func getAttribute_returnsNil_when_theAttributeIsMissing_when_file() throws {
        // Given
        let tmpDir = try #require(FileSystem.temporaryTestDirectory)
        let filePath = tmpDir.appending(component: "file.txt")
        try FileHandler.shared.touch(filePath)

        // When
        let got = try subject.getAttribute("foo", path: filePath)

        // Then
        #expect(got == nil)
    }

    @Test(.inTemporaryDirectory)
    func getAttribute_returnsNil_when_theAttributeIsMissing_when_directory() throws {
        // Given
        let tmpDir = try #require(FileSystem.temporaryTestDirectory)

        // When
        let got = try subject.getAttribute("foo", path: tmpDir)

        // Then
        #expect(got == nil)
    }

    @Test(.inTemporaryDirectory)
    func removeAttribute_removesTheAttribute_when_file() throws {
        // Given
        let tmpDir = try #require(FileSystem.temporaryTestDirectory)
        let filePath = tmpDir.appending(component: "file.txt")
        try FileHandler.shared.touch(filePath)

        // When
        try subject.setAttribute("foo", value: "bar", path: filePath)
        try subject.removeAttribute("foo", path: filePath)
        let got = try subject.getAttribute("foo", path: filePath)

        // Then
        #expect(got == nil)
    }

    @Test(.inTemporaryDirectory)
    func removeAttribute_removesTheAttribute_when_file_with_absent_attribute() throws {
        // Given
        let tmpDir = try #require(FileSystem.temporaryTestDirectory)
        let filePath = tmpDir.appending(component: "file.txt")
        try FileHandler.shared.touch(filePath)

        // When
        try subject.removeAttribute("foo", path: filePath)
        let got = try subject.getAttribute("foo", path: filePath)

        // Then
        #expect(got == nil)
    }

    @Test(.inTemporaryDirectory)
    func removeAttribute_removesTheAttribute_when_directory() throws {
        // Given
        let tmpDir = try #require(FileSystem.temporaryTestDirectory)

        // When
        try subject.setAttribute("foo", value: "bar", path: tmpDir)
        try subject.removeAttribute("foo", path: tmpDir)
        let got = try subject.getAttribute("foo", path: tmpDir)

        // Then
        #expect(got == nil)
    }

    @Test(.inTemporaryDirectory)
    func removeAttribute_removesTheAttribute_when_directory_with_absent_attribute() throws {
        // Given
        let tmpDir = try #require(FileSystem.temporaryTestDirectory)

        // When
        try subject.removeAttribute("foo", path: tmpDir)
        let got = try subject.getAttribute("foo", path: tmpDir)

        // Then
        #expect(got == nil)
    }
}
