import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistCore
import TuistSupport
import XcodeGraph
import XcodeProj
@testable import TuistGenerator
@testable import TuistTesting

struct WorkspaceSettingsDescriptorGeneratorTests {
    var subject: WorkspaceSettingsDescriptorGenerator!

    init() throws {
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock)
            .swiftVersion()
            .willReturn("5.2")

        subject = WorkspaceSettingsDescriptorGenerator()
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func generate_withoutGenerationOptions() {
        // Given
        let workspace = Workspace.test()

        // When
        let result = subject.generateWorkspaceSettings(workspace: workspace)

        // Then
        #expect(result == WorkspaceSettingsDescriptor(enableAutomaticXcodeSchemes: false))
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func generate_withGenerationOptions() {
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

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func generate_withRelativeDerivedDataPath() {
        // Given
        let workspace = Workspace.test(
            generationOptions: .test(
                enableAutomaticXcodeSchemes: nil,
                derivedDataPath: .custom("DerivedData")
            )
        )

        // When
        let result = subject.generateWorkspaceSettings(workspace: workspace)

        // Then
        #expect(
            result == WorkspaceSettingsDescriptor(
                enableAutomaticXcodeSchemes: nil,
                derivedDataPath: .custom("DerivedData")
            )
        )
        #expect(result?.settings.derivedDataLocationStyle == .workspaceRelativePath)
        #expect(result?.settings.derivedDataCustomLocation == "DerivedData")
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func generate_withAbsoluteDerivedDataPath() {
        // Given
        let workspace = Workspace.test(
            generationOptions: .test(
                enableAutomaticXcodeSchemes: nil,
                derivedDataPath: .custom("/tmp/DerivedData")
            )
        )

        // When
        let result = subject.generateWorkspaceSettings(workspace: workspace)

        // Then
        #expect(result?.settings.derivedDataLocationStyle == .absolutePath)
        #expect(result?.settings.derivedDataCustomLocation == "/tmp/DerivedData")
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func generate_withAllNilOptions() {
        // Given
        let workspace = Workspace.test(
            generationOptions: .test(
                enableAutomaticXcodeSchemes: nil
            )
        )

        // When
        let result = subject.generateWorkspaceSettings(workspace: workspace)

        // Then
        #expect(result == nil)
    }
}
