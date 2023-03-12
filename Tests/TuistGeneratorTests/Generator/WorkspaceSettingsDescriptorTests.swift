import Foundation
import TSCBasic
import XCTest
@testable import TuistGenerator

final class WorkspaceSettingsDescriptorTests: XCTestCase {
    func test_xcsettingsFilePath() {
        // Given
        let basePath = try! AbsolutePath(validating: "/temp")

        // When
        let actual = WorkspaceSettingsDescriptor.xcsettingsFilePath(relativeToWorkspace: basePath)

        // Then
        XCTAssertEqual(
            actual,
            try AbsolutePath(validating: "/temp/xcshareddata/WorkspaceSettings.xcsettings")
        )
    }
}
