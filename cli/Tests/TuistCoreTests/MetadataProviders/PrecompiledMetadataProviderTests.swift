import Foundation
import Path
import Testing
import TuistSupport
import XcodeGraph

@testable import TuistCore
@testable import TuistTesting

struct PrecompiledMetadataProviderTests {
    let subject: PrecompiledMetadataProvider

    init() {
        subject = PrecompiledMetadataProvider()
    }

    @Test func metadata_static() throws {
        // Given
        let binaryPath = SwiftTestingHelper.fixturePath(path: try RelativePath(validating: "libStaticLibrary.a"))

        // When
        let architectures = try subject.architectures(binaryPath: binaryPath)
        let linking = try subject.linking(binaryPath: binaryPath)
        let uuids = try subject.uuids(binaryPath: binaryPath)

        // Then
        #expect(architectures == [.x8664])
        #expect(linking == BinaryLinking.static)
        #expect(uuids == Set())
    }

    @Test func metadata_framework() throws {
        // Given
        let binaryPath = SwiftTestingHelper.fixturePath(path: try RelativePath(validating: "xpm.framework/xpm"))

        // When
        let architectures = try subject.architectures(binaryPath: binaryPath)
        let linking = try subject.linking(binaryPath: binaryPath)
        let uuids = try subject.uuids(binaryPath: binaryPath)

        // Then
        #expect(architectures == [.x8664, .arm64])
        #expect(linking == BinaryLinking.dynamic)
        #expect(
            uuids ==
                Set([
                    UUID(uuidString: "FB17107A-86FA-3880-92AC-C9AA9E04BA98"),
                    UUID(uuidString: "510FD121-B669-3524-A748-2DDF357A051C"),
                ])
        )
    }

    @Test func metadata_xcframework() throws {
        // Given
        let binaryPath =
            SwiftTestingHelper.fixturePath(
                path: try RelativePath(
                    validating: "MyFramework.xcframework/ios-x86_64-simulator/MyFramework.framework/MyFramework"
                )
            )

        // When
        let architectures = try subject.architectures(binaryPath: binaryPath)
        let linking = try subject.linking(binaryPath: binaryPath)
        let uuids = try subject.uuids(binaryPath: binaryPath)

        // Then
        #expect(architectures == [.x8664])
        #expect(linking == BinaryLinking.dynamic)
        #expect(
            uuids ==
                Set([
                    UUID(uuidString: "725302D8-8353-312F-8BF4-564B24F7B3E8"),
                ])
        )
    }

    @Test func metadata_static_xcframework() throws {
        // Given
        let binaryPath =
            SwiftTestingHelper
                .fixturePath(path: try RelativePath(validating: "MyStaticLibrary.xcframework/ios-arm64/libMyStaticLibrary.a"))

        // When
        let architectures = try subject.architectures(binaryPath: binaryPath)
        let linking = try subject.linking(binaryPath: binaryPath)
        let uuids = try subject.uuids(binaryPath: binaryPath)

        // Then
        #expect(architectures == [.arm64])
        #expect(linking == BinaryLinking.static)
        #expect(uuids == Set())
    }
}
