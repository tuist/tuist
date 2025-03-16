import Mockable
import ProjectDescription
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class ProjectDescriptionHelpersHasherTests: TuistUnitTestCase {
    private var subject: ProjectDescriptionHelpersHasher!
    private var machineEnvironment: MockMachineEnvironmentRetrieving!

    override func setUp() {
        super.setUp()
        given(swiftVersionProvider)
            .swiftVersion()
            .willReturn("5.2")
        machineEnvironment = .init()
        given(machineEnvironment)
            .macOSVersion
            .willReturn("15.2.4")
        subject = ProjectDescriptionHelpersHasher(
            tuistVersion: "3.2.1",
            machineEnvironment: machineEnvironment,
            swiftVersionProvider: swiftVersionProvider
        )
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_hash() async throws {
        // Given
        let temporaryDir = try temporaryPath()
        let helperPath = temporaryDir.appending(component: "Project+Templates.swift")
        try FileHandler.shared.write("import ProjectDescription", path: helperPath, atomically: true)
        environment.manifestLoadingVariables = ["TUIST_VARIABLE": "TEST"]

        // Then
        for _ in 0 ..< 20 {
            let got = try await subject.hash(helpersDirectory: temporaryDir)
            XCTAssertEqual(got, "5032b92c268cb7283c91ee37ec935c73")
        }
    }
}
