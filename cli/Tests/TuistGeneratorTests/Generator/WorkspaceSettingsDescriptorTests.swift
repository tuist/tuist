import Foundation
import Path
import Testing
@testable import TuistGenerator

struct WorkspaceSettingsDescriptorTests {
    @Test
    func test_xcsettingsFilePath() {
        // Given
        let basePath = try! AbsolutePath(validating: "/temp")

        // When
        let actual = WorkspaceSettingsDescriptor.xcsettingsFilePath(relativeToWorkspace: basePath)

        // Then
        #expect(actual == try AbsolutePath(validating: "/temp/xcshareddata/WorkspaceSettings.xcsettings"))
    }
}
