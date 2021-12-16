import Foundation
import TSCBasic
import XCTest
@testable import TuistGenerator

final class WorkspaceSettingsDescriptorTests: XCTestCase {
    func test_xcsettingsFilePath() {
        // Given
        let basePath = AbsolutePath("/temp")

        // When
        let actual = WorkspaceSettingsDescriptor.xcsettingsFilePath(relativeToWorkspace: basePath)

        // Then
        XCTAssertEqual(
            actual,
            AbsolutePath("/temp/xcshareddata/WorkspaceSettings.xcsettings")
        )
    }
}
