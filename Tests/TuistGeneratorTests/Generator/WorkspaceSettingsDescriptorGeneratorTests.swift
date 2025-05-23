import Foundation
import Mockable
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeGraph
import XcodeProj
import Testing
import FileSystem
import FileSystemTesting
@testable import TuistGenerator
@testable import TuistSupportTesting

@Suite(.inTemporaryDirectory, .withMockedSwiftVersionProvider)
struct WorkspaceSettingsDescriptorGeneratorTests {
    var subject: WorkspaceSettingsDescriptorGenerator!

    init() throws {
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock)
            .swiftVersion()
            .willReturn("5.2")

        subject = WorkspaceSettingsDescriptorGenerator()
    }

    @Test func test_generate_withoutGenerationOptions() {
        // Given
        let workspace = Workspace.test()

        // When
        let result = subject.generateWorkspaceSettings(workspace: workspace)

        // Then
        #expect(result == WorkspaceSettingsDescriptor(enableAutomaticXcodeSchemes: false))
    }

    @Test func test_generate_withGenerationOptions() {
        // Given
        let workspace = Workspace.test(
            generationOptions: .test(
                enableAutomaticXcodeSchemes: true
            )
        )

        // When
        let result = subject.generateWorkspaceSettings(workspace: workspace)

        // Then
        #expect(result == WorkspaceSettingsDescriptor(enableAutomaticXcodeSchemes: true))
    }
}
