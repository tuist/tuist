import Foundation
import Path
import Testing
@testable import TuistGenerator

struct WorkspaceSettingsDescriptorTests {
    @Test
    func test_xcsettingsFilePath() throws {
        // Given
        let basePath = try! AbsolutePath(validating: "/temp")

        // When
        let actual = WorkspaceSettingsDescriptor.xcsettingsFilePath(relativeToWorkspace: basePath)

        // Then
        let expected = try AbsolutePath(validating: "/temp/xcshareddata/WorkspaceSettings.xcsettings")
        #expect(actual == expected)
    }
}
