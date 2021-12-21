import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class WorkspaceSettingsDescriptorGeneratorTests: TuistUnitTestCase {
    var subject: WorkspaceSettingsDescriptorGenerator!

    override func setUp() {
        super.setUp()
        system.swiftVersionStub = { "5.2" }
        subject = WorkspaceSettingsDescriptorGenerator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_generate_withoutGenerationOptions() {
        // Given
        let workspace = Workspace.test()

        // When
        let result = subject.generateWorkspaceSettings(workspace: workspace)

        // Then
        XCTAssertNil(result)
    }

    func test_generate_withGenerationOptions() {
        // Given
        let workspace = Workspace.test(generationOptions: .options(automaticXcodeSchemes: .disabled))

        // When
        let result = subject.generateWorkspaceSettings(workspace: workspace)

        // Then
        XCTAssertEqual(result, WorkspaceSettingsDescriptor(automaticXcodeSchemes: false))
    }
}
