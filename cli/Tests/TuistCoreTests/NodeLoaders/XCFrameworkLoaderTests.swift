import FileSystemTesting
import Mockable
import Testing
import TuistSupport
import XcodeGraph
import XcodeMetadata

@testable import TuistCore
@testable import TuistTesting

struct XCFrameworkLoaderErrorTests {
    @Test func type_when_xcframeworkNotFound() {
        // Given
        let subject = XCFrameworkLoaderError.xcframeworkNotFound("/frameworks/tuist.xcframework")

        // Then
        #expect(subject.type == .abort)
    }

    @Test func description_when_xcframeworkNotFound() {
        // Given
        let subject = XCFrameworkLoaderError.xcframeworkNotFound("/frameworks/tuist.xcframework")

        // Then
        #expect(subject.description == "Couldn't find xcframework at /frameworks/tuist.xcframework")
    }
}

struct XCFrameworkLoaderTests {
    let xcframeworkMetadataProvider: MockXCFrameworkMetadataProviding
    let subject: XCFrameworkLoader

    init() {
        xcframeworkMetadataProvider = MockXCFrameworkMetadataProviding()
        subject = XCFrameworkLoader(xcframeworkMetadataProvider: xcframeworkMetadataProvider)
    }

    @Test(.inTemporaryDirectory) func load_throws_when_the_xcframework_doesnt_exist() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let xcframeworkPath = path.appending(component: "tuist.xcframework")

        // Then
        await #expect(throws: XCFrameworkLoaderError.xcframeworkNotFound(xcframeworkPath)) {
            try await subject.load(path: xcframeworkPath, expectedSignature: nil, status: .required)
        }
    }

    @Test(.inTemporaryDirectory) func load_when_the_xcframework_exists() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let xcframeworkPath = path.appending(component: "tuist.xcframework")
        let linking: BinaryLinking = .dynamic

        let infoPlist = XCFrameworkInfoPlist.test()
        try FileHandler.shared.touch(xcframeworkPath)

        given(xcframeworkMetadataProvider)
            .loadMetadata(at: .any, expectedSignature: .any, status: .any)
            .willProduce { path, _, _ in
                XCFrameworkMetadata(
                    path: path,
                    infoPlist: infoPlist,
                    linking: linking,
                    mergeable: false,
                    status: .required,
                    macroPath: nil
                )
            }

        // When
        let got = try await subject.load(path: xcframeworkPath, expectedSignature: nil, status: .required)

        // Then
        #expect(
            got ==
                .testXCFramework(
                    path: xcframeworkPath,
                    infoPlist: infoPlist,
                    linking: linking,
                    mergeable: false,
                    status: .required
                )
        )
    }
}
