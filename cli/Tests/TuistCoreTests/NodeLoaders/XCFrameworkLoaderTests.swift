import Mockable
import TuistSupport
import XcodeGraph
import XcodeMetadata
import XCTest

@testable import TuistCore
@testable import TuistTesting

final class XCFrameworkLoaderErrorTests: TuistUnitTestCase {
    func test_type_when_xcframeworkNotFound() {
        // Given
        let subject = XCFrameworkLoaderError.xcframeworkNotFound("/frameworks/tuist.xcframework")

        // Then
        XCTAssertEqual(subject.type, .abort)
    }

    func test_description_when_xcframeworkNotFound() {
        // Given
        let subject = XCFrameworkLoaderError.xcframeworkNotFound("/frameworks/tuist.xcframework")

        // Then
        XCTAssertEqual(subject.description, "Couldn't find xcframework at /frameworks/tuist.xcframework")
    }
}

final class XCFrameworkLoaderTests: TuistUnitTestCase {
    var xcframeworkMetadataProvider: MockXCFrameworkMetadataProviding!
    var subject: XCFrameworkLoader!

    override func setUp() {
        super.setUp()
        xcframeworkMetadataProvider = MockXCFrameworkMetadataProviding()
        subject = XCFrameworkLoader(xcframeworkMetadataProvider: xcframeworkMetadataProvider)
    }

    override func tearDown() {
        xcframeworkMetadataProvider = nil
        subject = nil
        super.tearDown()
    }

    func test_load_throws_when_the_xcframework_doesnt_exist() async throws {
        // Given
        let path = try temporaryPath()
        let xcframeworkPath = path.appending(component: "tuist.xcframework")

        // Then
        await XCTAssertThrowsSpecific(
            try await subject.load(path: xcframeworkPath, expectedSignature: nil, status: .required),
            XCFrameworkLoaderError.xcframeworkNotFound(xcframeworkPath)
        )
    }

    func test_load_when_the_xcframework_exists() async throws {
        // Given
        let path = try temporaryPath()
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
        XCTAssertEqual(
            got,
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
