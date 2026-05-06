import Foundation
import Path
import Testing
import XcodeGraph
@testable import XcodeMetadata

@Suite
struct PrecompiledMetadataProviderTests {
    var subject: PrecompiledMetadataProvider

    /// Initializes the test suite, setting up the required `PrecompiledMetadataProvider` instance.
    init() {
        subject = PrecompiledMetadataProvider()
    }

    @Test
    func metadataStatic() throws {
        // Given
        let binaryPath = AssertionsTesting.fixturePath(path: try RelativePath(validating: "libStaticLibrary.a"))

        // When
        let architectures = try subject.architectures(binaryPath: binaryPath)
        let linking = try subject.linking(binaryPath: binaryPath)
        let uuids = try subject.uuids(binaryPath: binaryPath)

        // Then
        #expect(architectures == [.x8664], "Architectures do not match expected value")
        #expect(linking == BinaryLinking.static, "Linking does not match expected value")
        #expect(uuids == Set(), "UUIDs do not match expected value")
    }

    @Test
    func metadataFramework() throws {
        // Given
        let binaryPath = AssertionsTesting.fixturePath(path: try RelativePath(validating: "xpm.framework/xpm"))

        // When
        let architectures = try subject.architectures(binaryPath: binaryPath)
        let linking = try subject.linking(binaryPath: binaryPath)
        let uuids = try subject.uuids(binaryPath: binaryPath)

        // Then
        #expect(architectures == [.x8664, .arm64], "Architectures do not match expected value")
        #expect(linking == BinaryLinking.dynamic, "Linking does not match expected value")
        #expect(
            uuids == Set([
                UUID(uuidString: "FB17107A-86FA-3880-92AC-C9AA9E04BA98"),
                UUID(uuidString: "510FD121-B669-3524-A748-2DDF357A051C"),
            ]),
            "UUIDs do not match expected value"
        )
    }

    @Test
    func metadataXCFramework() throws {
        // Given
        let binaryPath = AssertionsTesting.fixturePath(
            path: try RelativePath(
                validating: "MyFramework.xcframework/ios-x86_64-simulator/MyFramework.framework/MyFramework"
            )
        )

        // When
        let architectures = try subject.architectures(binaryPath: binaryPath)
        let linking = try subject.linking(binaryPath: binaryPath)
        let uuids = try subject.uuids(binaryPath: binaryPath)

        // Then
        #expect(architectures == [.x8664], "Architectures do not match expected value")
        #expect(linking == BinaryLinking.dynamic, "Linking does not match expected value")
        #expect(
            uuids == Set([
                UUID(uuidString: "725302D8-8353-312F-8BF4-564B24F7B3E8"),
            ]),
            "UUIDs do not match expected value"
        )
    }

    @Test
    func metadataStaticXCFramework() throws {
        // Given
        let binaryPath = AssertionsTesting.fixturePath(
            path: try RelativePath(validating: "MyStaticLibrary.xcframework/ios-arm64/libMyStaticLibrary.a")
        )

        // When
        let architectures = try subject.architectures(binaryPath: binaryPath)
        let linking = try subject.linking(binaryPath: binaryPath)
        let uuids = try subject.uuids(binaryPath: binaryPath)

        // Then
        #expect(architectures == [.arm64], "Architectures do not match expected value")
        #expect(linking == BinaryLinking.static, "Linking does not match expected value")
        #expect(uuids == Set(), "UUIDs do not match expected value")
    }
}
